{ lib
, stdenv
, callPackage
, stdenvNoCC
, fetchurl
, rpmextract
, undmg
, darwin
, validatePkgConfig
, enableStatic ? stdenv.hostPlatform.isStatic
}:

/*
  For details on using mkl as a blas provider for python packages such as numpy,
  numexpr, scipy, etc., see the Python section of the NixPkgs manual.
*/
let
  # Release notes and download URLs are here:
  # https://registrationcenter.intel.com/en/products/
  version = "${mklVersion}.${rel}";

  # Darwin is pinned to 2019.3 because the DMG does not unpack; see here for details:
  # https://github.com/matthewbauer/undmg/issues/4
  mklVersion = if stdenvNoCC.isDarwin then "2019.3" else "2023.0.0";
  rel = if stdenvNoCC.isDarwin then "199" else "25398";

  # Intel openmp uses its own versioning.
  openmpVersion = if stdenvNoCC.isDarwin then "19.0.3" else "2023.0.0";
  openmpRel = "25370";

  # Thread Building Blocks release.
  tbbVersion = if stdenvNoCC.isDarwin then "2019.3" else "2021.8.0";
  tbbRel = "25334";

  shlibExt = stdenvNoCC.hostPlatform.extensions.sharedLibrary;

  oneapi-mkl = fetchurl {
    url = "https://yum.repos.intel.com/oneapi/intel-oneapi-mkl-${mklVersion}-${mklVersion}-${rel}.x86_64.rpm";
    hash = "sha256-fiL5TDmQHB+OQb1ERcoDQFpUutpsPe+AqIbMoa85nEk=";
  };

  oneapi-mkl-common = fetchurl {
    url = "https://yum.repos.intel.com/oneapi/intel-oneapi-mkl-common-${mklVersion}-${mklVersion}-${rel}.noarch.rpm";
    hash = "sha256-AFayUxybi48SgR2mX6mxkNECconIXm1/TWelvE4aqX0=";
  };

  oneapi-mkl-common-devel = fetchurl {
    url = "https://yum.repos.intel.com/oneapi/intel-oneapi-mkl-common-devel-${mklVersion}-${mklVersion}-${rel}.noarch.rpm";
    hash = "sha256-riyIO2xWuvTSzfXgB+K6NSKqWLRmxKSnGZaH5nYTYPk=";
  };

  oneapi-mkl-devel = fetchurl {
    url = "https://yum.repos.intel.com/oneapi/intel-oneapi-mkl-devel-${mklVersion}-${mklVersion}-${rel}.x86_64.rpm";
    hash = "sha256-2IK0t47FaPNp7Oq9LJ5ZdLmlFFjQluWrh+nhvi8MCd8=";
  };

  oneapi-openmp = fetchurl {
    url = "https://yum.repos.intel.com/oneapi/intel-oneapi-openmp-${mklVersion}-${mklVersion}-${openmpRel}.x86_64.rpm";
    hash = "sha256-grzVFWqt3Vpwb5K3Bur+sJz8pdKxZ4ISJXF5YAPrwmk=";
  };

  oneapi-tbb = fetchurl {
    url = "https://yum.repos.intel.com/oneapi/intel-oneapi-tbb-${tbbVersion}-${tbbVersion}-${tbbRel}.x86_64.rpm";
    hash = "sha256-8hIoRfV36XVElKCqP9UmCkjLCs3l0ZKCHxg+yxNIHc0=";
  };

in stdenvNoCC.mkDerivation ({
  pname = "mkl";
  inherit version;

  dontUnpack = stdenvNoCC.isLinux;

  nativeBuildInputs = [ validatePkgConfig ] ++ (if stdenvNoCC.isDarwin
    then
      [ undmg darwin.cctools ]
    else
      [ rpmextract ]);

  buildPhase = if stdenvNoCC.isDarwin then ''
    for f in Contents/Resources/pkg/*.tgz; do
      tar xzvf $f
    done
  '' else ''
    rpmextract ${oneapi-mkl}
    rpmextract ${oneapi-mkl-common}
    rpmextract ${oneapi-mkl-common-devel}
    rpmextract ${oneapi-mkl-devel}
    rpmextract ${oneapi-openmp}
    rpmextract ${oneapi-tbb}
  '';

  installPhase = if stdenvNoCC.isDarwin then ''
    for f in $(find . -name 'mkl*.pc') ; do
      bn=$(basename $f)
      substituteInPlace $f \
        --replace "prefix=<INSTALLDIR>/mkl" "prefix=$out" \
        --replace $\{MKLROOT} "$out" \
        --replace "lib/intel64_lin" "lib" \
        --replace "lib/intel64" "lib"
    done
    for f in $(find opt/intel -name 'mkl*iomp.pc') ; do
      substituteInPlace $f \
        --replace "../compiler/lib" "lib"
    done

    mkdir -p $out/lib

    cp -r compilers_and_libraries_${version}/mac/mkl/include $out/

    cp -r compilers_and_libraries_${version}/licensing/mkl/en/license.txt $out/lib/
    cp -r compilers_and_libraries_${version}/mac/compiler/lib/* $out/lib/
    cp -r compilers_and_libraries_${version}/mac/mkl/lib/* $out/lib/
    cp -r compilers_and_libraries_${version}/mac/tbb/lib/* $out/lib/

    mkdir -p $out/lib/pkgconfig
    cp -r compilers_and_libraries_${version}/mac/mkl/bin/pkgconfig/* $out/lib/pkgconfig
  '' else ''
    for f in $(find . -name 'mkl*.pc') ; do
      bn=$(basename $f)
      substituteInPlace $f \
        --replace $\{MKLROOT} "$out" \
        --replace "lib/intel64" "lib"

      sed -r -i "s|^prefix=.*|prefix=$out|g" $f
    done

    for f in $(find opt/intel -name 'mkl*iomp.pc') ; do
      substituteInPlace $f --replace "../compiler/lib" "lib"
    done

    # License
    install -Dm0655 -t $out/share/doc/mkl opt/intel/oneapi/mkl/${mklVersion}/licensing/license.txt

    # Dynamic libraries
    mkdir -p $out/lib
    cp -a opt/intel/oneapi/mkl/${mklVersion}/lib/intel64/*.so* $out/lib
    cp -a opt/intel/oneapi/compiler/${mklVersion}/linux/compiler/lib/intel64_lin/*.so* $out/lib
    cp -a opt/intel/oneapi/tbb/${tbbVersion}/lib/intel64/gcc4.8/*.so* $out/lib

    # Headers
    cp -r opt/intel/oneapi/mkl/${mklVersion}/include $out/

    # CMake config
    cp -r opt/intel/oneapi/mkl/${mklVersion}/lib/cmake $out/lib
  '' +
    (if enableStatic then ''
      install -Dm0644 -t $out/lib opt/intel/oneapi/mkl/${mklVersion}/lib/intel64/*.a
      install -Dm0644 -t $out/lib/pkgconfig opt/intel/oneapi/mkl/${mklVersion}/tools/pkgconfig/*.pc
    '' else ''
      cp opt/intel/oneapi/mkl/${mklVersion}/lib/intel64/*.so* $out/lib
      install -Dm0644 -t $out/lib/pkgconfig opt/intel/oneapi/mkl/${mklVersion}/lib/pkgconfig/*dynamic*.pc
    '') + ''
    # Setup symlinks for blas / lapack
    ln -s $out/lib/libmkl_rt${shlibExt} $out/lib/libblas${shlibExt}
    ln -s $out/lib/libmkl_rt${shlibExt} $out/lib/libcblas${shlibExt}
    ln -s $out/lib/libmkl_rt${shlibExt} $out/lib/liblapack${shlibExt}
    ln -s $out/lib/libmkl_rt${shlibExt} $out/lib/liblapacke${shlibExt}
  '' + lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
    ln -s $out/lib/libmkl_rt${shlibExt} $out/lib/libblas${shlibExt}".3"
    ln -s $out/lib/libmkl_rt${shlibExt} $out/lib/libcblas${shlibExt}".3"
    ln -s $out/lib/libmkl_rt${shlibExt} $out/lib/liblapack${shlibExt}".3"
    ln -s $out/lib/libmkl_rt${shlibExt} $out/lib/liblapacke${shlibExt}".3"
  '';

  # fixDarwinDylibName fails for libmkl_cdft_core.dylib because the
  # larger updated load commands do not fit. Use install_name_tool
  # explicitly and ignore the error.
  postFixup = lib.optionalString stdenvNoCC.isDarwin ''
    for f in $out/lib/*.dylib; do
      install_name_tool -id $out/lib/$(basename $f) $f || true
    done
    install_name_tool -change @rpath/libiomp5.dylib $out/lib/libiomp5.dylib $out/lib/libmkl_intel_thread.dylib
    install_name_tool -change @rpath/libtbb.dylib $out/lib/libtbb.dylib $out/lib/libmkl_tbb_thread.dylib
    install_name_tool -change @rpath/libtbbmalloc.dylib $out/lib/libtbbmalloc.dylib $out/lib/libtbbmalloc_proxy.dylib
  '';

  # Per license agreement, do not modify the binary
  dontStrip = true;
  dontPatchELF = true;

  passthru.tests = {
    pkg-config-dynamic-iomp = callPackage ./test { enableStatic = false; execution = "iomp"; };
    pkg-config-static-iomp = callPackage ./test { enableStatic = true; execution = "iomp"; };
    pkg-config-dynamic-seq = callPackage ./test { enableStatic = false; execution = "seq"; };
    pkg-config-static-seq = callPackage ./test { enableStatic = true; execution = "seq"; };
  };

  meta = with lib; {
    description = "Intel OneAPI Math Kernel Library";
    longDescription = ''
      Intel OneAPI Math Kernel Library (Intel oneMKL) optimizes code with minimal
      effort for future generations of Intel processors. It is compatible with your
      choice of compilers, languages, operating systems, and linking and
      threading models.
    '';
    homepage = "https://software.intel.com/en-us/mkl";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.issl;
    platforms = [ "x86_64-linux" "x86_64-darwin" ];
    maintainers = with maintainers; [ bhipple ];
  };
} // lib.optionalAttrs stdenvNoCC.isDarwin {
  src = fetchurl {
    url = "http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/15235/m_mkl_${version}.dmg";
    sha256 = "14b3ciz7995sqcd6jz7hc8g2x4zwvqxmgxgni46vrlb7n523l62f";
  };
})
