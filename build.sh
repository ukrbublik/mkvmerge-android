#!/bin/bash

#./build.sh --use-crystalx --crystalx-dir=$HOME/projs/crystax-ndk-10.3.2 --api=21 --out-dir="$PWD/out_crx" 
#./build.sh --api=21 --out="$PWD/out" --abi="armeabi-v7a"

########################### funcs

# usage: 
#  arr=("a" "b")
#  if (array_contains arr "a"); then echo "works"; else echo "not works"; fi
array_contains () {
  # odd syntax here for passing array parameters: http://stackoverflow.com/questions/8082947/how-to-pass-an-array-to-a-bash-function
  local list=$1[@]
  local elem=$2
  for i in "${!list}"
  do
    if [ "$i" == "${elem}" ] ; then
      return 0
    fi
  done
  return 1
}


########################### configurable vars

_ALL_ARCHS=("arm" "arm64" "mips" "mips64" "x86" "x86_64") # see target "toolchain", "make_standalone_toolchain.py --help"
_ALL_ABIS=("armeabi" "armeabi-v7a" "armeabi-v7a-hard" "arm64-v8a" "mips" "mips64" "x86" "x86_64")
_ALL_GCC_VERSIONS=("4.9" "5")

# defaults
_DEFAULT_SDK_DIR="$HOME/Android/Sdk"
_DEFAULT_ABI="armeabi-v7a"
_DEFAULT_APILEVEL=21
_DEFAULT_OUTS_DIR="$PWD/out"
_DEFAULT_TOOLCHAINS_DIR="$PWD/toolchains"
_DEFAULT_GCC_VERSION="4.9"

# set default vals for cmd args
_SDK_DIR="$_DEFAULT_SDK_DIR"
_ABI="$_DEFAULT_ABI"
_APILEVEL="$_DEFAULT_APILEVEL"
_OUTS_DIR="$_DEFAULT_OUTS_DIR"
_TOOLCHAINS_DIR="$_DEFAULT_TOOLCHAINS_DIR"
_CRYSTALX_DIR=""
_FORCE=0
_USE_CRYSTALX=0
_GCC_VERSION="$_DEFAULT_GCC_VERSION"

########################### parse cmd args

for option
do
  case $option in

  -help | --help | -h)
    _WANT_HELP="YES" ;;

  -sdk-dir=* | --sdk-dir=*)
    _SDK_DIR=`expr "x$option" : "x-*sdk-dir=\(.*\)"`
    ;;

  -out-dir=* | --out-dir=*)
    _OUTS_DIR=`expr "x$option" : "x-*out-dir=\(.*\)"`
    ;;

  -toolchains-dir=* | --toolchains-dir=*)
    _TOOLCHAINS_DIR=`expr "x$option" : "x-*toolchains-dir=\(.*\)"`
    ;;

  -crystalx-dir=* | --crystalx-dir=*)
    _CRYSTALX_DIR=`expr "x$option" : "x-*crystalx-dir=\(.*\)"`
    ;;

  -use-crystalx | --use-crystalx)
    _USE_CRYSTALX=1
    ;;

  -gcc-ver=* | --gcc-ver=*)
    _GCC_VERSION=`expr "x$option" : "x-*gcc-ver=\(.*\)"`
    ;;

  -force | --force)
    _FORCE=1
    ;;

  -arch=* | --arch=*)
    _ARCH=`expr "x$option" : "x-*arch=\(.*\)"`
    ;;

  -api=* | --api=*)
    _APILEVEL=`expr "x$option" : "x-*api=\(.*\)"`
    ;;

  -*)
    {
      echo "ERROR: unrecognized option: $option"
      echo "Try \`$0 --help' for more information." >&2
      { exit 1; }
    }
    ;; 

  esac
done


########################### show help

if test "x$_WANT_HELP" = xYES; then
  cat <<EOF
\`./build.sh' builds libs need for mkvtoolnix.

Usage: $0 [OPTION]... 

Defaults for the options are specified in brackets.

Configuration:
  -h, --help                Display this help and exit
  --out-dir=PATH            Output path
                            [$_DEFAULT_OUTS_DIR]
  --toolchains-dir=path     Path for toolchains
                            [$_DEFAULT_TOOLCHAINS_DIR]
  --sdk-dir=PATH            Path to Android SDK, will be used to get path to official NDK
                            [$_DEFAULT_SDK_DIR]
  --crystalx-dir=PATH       Path to CrystalX
  --use-crystalx            To use CrystalX instead of official NDK
                            [no]
  --abi=ABI                 Target abi (arch), one of: ${_ALL_ABIS[*]}
                            [$_DEFAULT_ABI]
  --api=APILEVEL            Android API level
                            [$_DEFAULT_APILEVEL]
  --force                   Force rebuild all targets (also clean before make)
                            [no]
  --gcc-ver                 GCC version, one of: ${_ALL_GCC_VERSIONS[*]}
                            [$_DEFAULT_GCC_VERSION]

EOF
fi
test -n "$_WANT_HELP" && exit 0


########################### check cmd args

if ! (array_contains _ALL_ABIS $_ABI); then
  echo "Incorrect value of --abi. Should be one of: ${_ALL_ABIS[*]}"
  exit 1
fi


########################### vars

_GCC="gcc"
_GPP="g++"

_ARCH=
_TOOLCHAIN_NAME=
_PREBUILT_BIN_PREFIX=
_NDK_DIR=
_TOOLCHAIN_DIR=
_HOST=
_TARGET=
_TARGET_3=
_TARGET_2=
_TARGET_3alt=
_GCC_FULL=
_GPP_FULL=
_LD_FULL=
_NDK_SYSROOT=
_NDK_STL=
_NDK_PREBUILT=
PREBUILT=
PLATFORM=
_EXTRA_ARGS=
_COMMON_CFLAGS=
_COMMON_LDFLAGS=
_LDFLAGS_NDK_SYSROOT=
_CPPFLAGS_NDK_SYSROOT=
_LDFLAGS_NDK_STL=
_CPPFLAGS_NDK_STL=
_LDFLAGS_CRYSTALX=
_LDFLAGS_OUT=
_CPPFLAGS_OUT=
_OUT_DIR=

# define $ARCH
case $_ABI in
  armeabi*)
    _ARCH=arm
    ;;
  arm64*)
    _ARCH=arm64
    ;;
  x86|x86_64|mips|mips64)
    _ARCH=$_ABI
    ;;
  *)
    echo "ERROR: Unknown ABI: '$_ABI'" 1>&2
    exit 1
esac

# define toolchain name and bins prefix
case $_ABI in
  armeabi*)
    _TOOLCHAIN_NAME=arm-linux-androideabi
    _PREBUILT_BIN_PREFIX=$_TOOLCHAIN_NAME
    ;;
  x86)
    _TOOLCHAIN_NAME=x86
    _PREBUILT_BIN_PREFIX=i686-linux-android
    ;;
  mips)
    _TOOLCHAIN_NAME=mipsel-linux-android
    _PREBUILT_BIN_PREFIX=$_TOOLCHAIN_NAME
    ;;
  arm64-v8a)
    _TOOLCHAIN_NAME=aarch64-linux-android
    _PREBUILT_BIN_PREFIX=$_TOOLCHAIN_NAME
    ;;
  x86_64)
    _TOOLCHAIN_NAME=x86_64
    _PREBUILT_BIN_PREFIX=$_TOOLCHAIN_NAME
    ;;
  mips64)
    _TOOLCHAIN_NAME=mips64el-linux-android
    _PREBUILT_BIN_PREFIX=$_TOOLCHAIN_NAME
    ;;
  *)
    echo "ERROR: Unknown ABI: '$_ABI'" 1>&2
    exit 1
esac

# define ndk pathes
if [ $_USE_CRYSTALX -eq 1 ]; then
  _NDK_DIR="$_CRYSTALX_DIR"
else
  _NDK_DIR="${_SDK_DIR}/ndk-bundle"
fi
_NDK_SYSROOT="${_NDK_DIR}/platforms/android-${_APILEVEL}/arch-${_ARCH}"
_NDK_STL="${_NDK_DIR}/sources/cxx-stl/gnu-libstdc++/$_GCC_VERSION"

# define toolchain path
if [ $_USE_CRYSTALX -eq 1 ]; then
  _TOOLCHAIN_DIR="${_TOOLCHAINS_DIR}/crx/${_ARCH}"
else
  _TOOLCHAIN_DIR="${_TOOLCHAINS_DIR}/off/${_ARCH}"
fi

# define host
case $_ABI in
  armeabi*)
    _HOST=arm-linux-androideabi
    ;;
  arm64*)
    _HOST=aarch64-linux-android
    ;;
  x86)
    _HOST=i686-linux-android
    ;;
  x86_64)
    _HOST=x86_64-linux-android
    ;;
  mips)
    _HOST=mipsel-linux-android
    ;;
  mips64)
    _HOST=mips64el-linux-android
    ;;
  *)
    echo "ERROR: Unknown ABI: '$_ABI'" 1>&2
    exit 1
esac

# define target
_TARGET=$_HOST
_TARGET_3=$_TARGET
_TARGET_2=$_TARGET_3
_TARGET_3alt=$_TARGET_3
if [ $_ARCH == "arm" ]; then
  _TARGET_2="arm-eabi"
  _TARGET_3alt="arm-linux-eabi"
fi

# define other stuff
_OUT_DIR="$_OUTS_DIR/$_ABI"
_GCC_FULL="${_PREBUILT_BIN_PREFIX}-${_GCC}"
_GPP_FULL="${_PREBUILT_BIN_PREFIX}-${_GPP}"
_LD_FULL="${_PREBUILT_BIN_PREFIX}-ld"
_NDK_PREBUILT="${_NDK_DIR}/toolchains/${_TOOLCHAIN_NAME}-${_GCC_VERSION}"
PREBUILT="$_NDK_PREBUILT"
PLATFORM="$_NDK_SYSROOT"

# define compiling/linking flags
_EXTRA_ARGS=""
case $_ABI in
  armeabi-v7a*)
    _EXTRA_ARGS="$_EXTRA_ARGS --enable-arm-neon=api"
esac

_COMMON_CFLAGS=""
case $_ABI in
  armeabi)
    _COMMON_CFLAGS="-march=armv5te -mtune=xscale -msoft-float"
    ;;
  armeabi-v7a)
    _COMMON_CFLAGS="-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp"
    ;;
  armeabi-v7a-hard)
    _COMMON_CFLAGS="-march=armv7-a -mfpu=vfpv3-d16 -mhard-float"
    ;;
  *)
    _COMMON_CFLAGS=""
esac
case $_ABI in
  armeabi*)
    _COMMON_CFLAGS="$_COMMON_CFLAGS -mthumb"
esac
_COMMON_CFLAGS="$_COMMON_CFLAGS --sysroot=$_NDK_SYSROOT"

_COMMON_LDFLAGS=""
if [ "$_ABI" = "armeabi-v7a-hard" ]; then
    _COMMON_LDFLAGS="$_COMMON_LDFLAGS -Wl,--no-warn-mismatch"
fi

_LDFLAGS_NDK_SYSROOT="-Wl,-rpath-link=$_NDK_SYSROOT/usr/lib/ -L$_NDK_SYSROOT/usr/lib/"
_CPPFLAGS_NDK_SYSROOT="-I$_NDK_SYSROOT/usr/include/"
_LDFLAGS_OUT="-L$_OUT_DIR/lib/"
_CPPFLAGS_OUT="-I$_OUT_DIR/include/"
_LDFLAGS_NDK_STL="-L$_NDK_STL/libs/$_ABI/"
_CPPFLAGS_NDK_STL="-I$_NDK_STL/include/"
_LDFLAGS_CRYSTALX="-L$_NDK_DIR/sources/crystax/libs/$_ABI"

export ANDROID_HOME="$_SDK_DIR"
export TOOLCHAIN="$_TOOLCHAIN_DIR"

########################### show config

echo ""
echo "Config:"
echo "Android SDK path: $_SDK_DIR"
echo "Android NDK path: $_NDK_DIR"
echo "CrystalX path: $_CRYSTALX_DIR"
echo "Use CrystalX: $_USE_CRYSTALX"
echo "Android API: $_APILEVEL"
echo "ABI: $_ABI"
echo "Arch: $_ARCH"
echo "Toolchain path: $_TOOLCHAIN_DIR"
echo "Out build path: $_OUT_DIR"
echo "Force recompiling all: $_FORCE"
echo ""


########################### 0 - check Android NDK installed

#if [ $_USE_CRYSTALX -eq 0 ] && ! [ -d $_SDK_DIR ]; then
#  echo "Android SDK is not installed to $_SDK_DIR"
#  exit 1
#fi
if ! [ -d $_NDK_DIR ]; then
  echo "Android NDK is not installed to $_NDK_DIR"
  exit 1
fi
if ! [ -d $_NDK_SYSROOT ]; then
  echo "Android NDK API level $_APILEVEL for arch $_ARCH is not installed to $_NDK_SYSROOT"
  exit 1
fi


########################### 0 - install toolchain

# for official NDK
if [ $_USE_CRYSTALX -eq 0 ]; then
  if ! [ -d $_TOOLCHAIN_DIR ]; then
    _FORCE_FLAG=""
    if [ $_FORCE -eq 1 ]; then
      _FORCE_FLAG=" --force "
    fi

    echo "*** Preparing official toolchain..."
    # todo: --stl=? (Specify C++ STL [gnustl])
    $_NDK_DIR/build/tools/make_standalone_toolchain.py $_FORCE_FLAG -v --arch $_ARCH --api $_APILEVEL --install-dir "$_TOOLCHAIN_DIR"
    if ! [ $? -eq 0 ]; then exit 1; fi
    echo "*** Official toolchain has been installed to $_TOOLCHAIN_DIR"
  else
    echo "*** Official toolchain is already installed to $_TOOLCHAIN_DIR"
  fi
  echo ""
fi

# for CrystalX
if [ $_USE_CRYSTALX -eq 1 ]; then
  if ! [ -d $_TOOLCHAIN_DIR ]; then
    echo "*** Preparing CrystalX toolchain..."
    # todo --stl ? {gnustl,libc++,stlport}
    $_NDK_DIR/build/tools/make-standalone-toolchain.sh --verbose --arch=$_ARCH --platform="android-${_APILEVELAPI}" --ndk-dir="$_NDK_DIR" --install-dir="$_TOOLCHAIN_DIR"
    if ! [ $? -eq 0 ]; then exit 1; fi
    echo "*** CrystalX toolchain has been installed to $_TOOLCHAIN_DIR"
  else
    echo "*** CrystalX toolchain is already installed to $_TOOLCHAIN_DIR"
  fi
  echo ""
fi

# todo https://github.com/crystax/android-toolchain-build


########################### 1 - build ogg

if (! [ -f "${_OUT_DIR}/lib/libogg.a" ]) || [ $_FORCE -eq 1 ]; then
  echo "*** Compiling libogg..."

  # todo download http://downloads.xiph.org/releases/ogg/libogg-1.3.2.zip
  
  cd libogg # todo names
  _PATH=$PATH
  export PATH="$_TOOLCHAIN_DIR/bin:$_TOOLCHAIN_DIR/$_TARGET/bin:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$PATH"

  # tip: for triplet host 'arm-linux-androideabi' will return: Invalid configuration `arm-linux-androideabi': system `androideabi' not recognized
  ./configure -q \
    --host="$_TARGET_3alt" \
    --target="$_TARGET_3" \
    --prefix="$_OUT_DIR" \
    --disable-shared \
    --enable-static \
    --with-pic \
    CC="$_GCC_FULL" \
    CFLAGS="" \
    LDFLAGS="$_COMMON_LDFLAGS $_LDFLAGS_NDK_SYSROOT" \
    CPPFLAGS="$_COMMON_CFLAGS $_CPPFLAGS_NDK_SYSROOT -DANDROID -fPIC " \
    LIBS="-lc"

  #if [ $_FORCE -eq 1 ]; then
    make clean V=0 -s
    if ! [ $? -eq 0 ]; then exit 1; fi
  #fi
  if ! [ $? -eq 0 ]; then exit 1; fi
  make V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi
  make install V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi

  cd ..
  export PATH=$_PATH

  echo "*** libogg has been compiled"
else
  echo "*** libogg is already compiled"
fi
echo ""


########################### 2 - build vorbis

if (! [ -f "${_OUT_DIR}/lib/libvorbis.a" ]) || [ $_FORCE -eq 1 ]; then
  echo "*** Compiling libvorbis..."

  # todo download http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.5.zip

  cd libvorbis # todo names
  _PATH=$PATH
  export PATH="$_TOOLCHAIN_DIR/bin:$_TOOLCHAIN_DIR/$_TARGET/bin:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$PATH"

  ./configure -q \
    --host="$_TARGET_3" \
    --target="$_TARGET_3" \
    --prefix="$_OUT_DIR" \
    --disable-shared \
    --enable-static \
    --with-pic \
    CC="$_GCC_FULL" \
    CFLAGS="" \
    LDFLAGS="$_COMMON_LDFLAGS $_LDFLAGS_NDK_SYSROOT $_LDFLAGS_OUT" \
    CPPFLAGS="$_COMMON_CFLAGS $_CPPFLAGS_NDK_SYSROOT $_CPPFLAGS_OUT -DANDROID -fPIC  -Wno-unused-function -Wno-unused-variable" \
    LIBS="-lc -lm -logg"

  #if [ $_FORCE -eq 1 ]; then
    make clean V=0 -s
    if ! [ $? -eq 0 ]; then exit 1; fi
  #fi
  if ! [ $? -eq 0 ]; then exit 1; fi
  make V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi
  make install V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi

  cd ..
  export PATH=$_PATH

  echo "*** libvorbis has been compiled"
else
  echo "*** libvorbis is already compiled"
fi
echo ""


########################### 3 - build ebml

if (! [ -f "${_OUT_DIR}/lib/libebml.a" ]) || [ $_FORCE -eq 1 ]; then
  echo "*** Compiling libebml..."

  # todo git https://github.com/Matroska-Org/libebml
  
  cd libebml # todo names
  _PATH=$PATH
  export PATH="$_TOOLCHAIN_DIR/bin:$_TOOLCHAIN_DIR/$_TARGET/bin:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$PATH"

  ./configure -q \
    --host="$_TARGET_2" \
    --target="$_TARGET_3" \
    --prefix="$_OUT_DIR" \
    --disable-shared \
    --enable-static \
    --with-pic \
    CXX="$_GPP_FULL" \
    CXXFLAGS="" \
    LDFLAGS="$_COMMON_LDFLAGS $_LDFLAGS_NDK_SYSROOT" \
    CPPFLAGS="$_COMMON_CFLAGS $_CPPFLAGS_NDK_SYSROOT -DANDROID -fPIC  -Wno-shadow" \
    LIBS="-lc"

  #if [ $_FORCE -eq 1 ]; then
    make clean V=0 -s
    if ! [ $? -eq 0 ]; then exit 1; fi
  #fi
  if ! [ $? -eq 0 ]; then exit 1; fi
  make V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi
  make install V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi

  cd ..
  export PATH=$_PATH

  echo "*** libebml has been compiled"
else
  echo "*** libebml is already compiled"
fi
echo ""

export EBML_CFLAGS="$_CPPFLAGS_OUT"
export EBML_LIBS="$_LDFLAGS_OUT"


########################### 4 - build matroska

if (! [ -f "${_OUT_DIR}/lib/libmatroska.a" ]) || [ $_FORCE -eq 1 ]; then
  echo "*** Compiling libmatroska..."

  # todo git https://github.com/Matroska-Org/libmatroska
  
  cd libmatroska # todo names
  _PATH=$PATH
  export PATH="$_TOOLCHAIN_DIR/bin:$_TOOLCHAIN_DIR/$_TARGET/bin:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$PATH"

  ./configure -q \
    --host="$_TARGET_2" \
    --target="$_TARGET_3" \
    --prefix="$_OUT_DIR" \
    --disable-shared \
    --enable-static \
    --with-pic \
    CXX="$_GPP_FULL" \
    CXXFLAGS="" \
    LDFLAGS="$_COMMON_LDFLAGS $_LDFLAGS_NDK_SYSROOT $_LDFLAGS_OUT" \
    CPPFLAGS="$_COMMON_CFLAGS $_CPPFLAGS_NDK_SYSROOT $_CPPFLAGS_OUT -DANDROID -fPIC " \
    LIBS="-lc -lm -lebml"

  #if [ $_FORCE -eq 1 ]; then
    make clean V=0 -s
    if ! [ $? -eq 0 ]; then exit 1; fi
  #fi
  if ! [ $? -eq 0 ]; then exit 1; fi
  make V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi
  make install V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi

  cd ..
  export PATH=$_PATH

  echo "*** libmatroska has been compiled"
else
  echo "*** libmatroska is already compiled"
fi
echo ""


########################### 5 - build boost

# also see https://github.com/moritz-wundke/Boost-for-Android
# also see https://www.crystax.net/ru/blog/2
#  https://habrahabr.ru/post/253233/
#  ready build can be found @ crystax-ndk-10.3.2/sources/boost/1.59.0/libs/armeabi/gnu-4.9

# todo! build-boost.sh (посмотри, что есть полезного)

if (! ([ -f "${_OUT_DIR}/lib/libboost_filesystem.a" ] \
   && [ -f "${_OUT_DIR}/lib/libboost_system.a" ] \
   && [ -f "${_OUT_DIR}/lib/libboost_iostreams.a" ] \
   && [ -f "${_OUT_DIR}/lib/libboost_regex.a" ] \
   && [ -f "${_OUT_DIR}/lib/libboost_math_c99.a" ] \
   && [ -f "${_OUT_DIR}/lib/libboost_math_c99f.a" ] \
   && [ -f "${_OUT_DIR}/lib/libboost_math_c99l.a" ] \
   && [ -f "${_OUT_DIR}/lib/libboost_date_time.a" ] \
  ) || [ $_FORCE -eq 1 ]); then
  echo "*** Compiling boost..."

  # todo git https://github.com/ukrbublik/android-vendor-boost-1-62-0

  cd android-vendor-boost-1-62-0 # todo names

  ./bootstrap.sh \
    --prefix="$_OUT_DIR" \
    --exec-prefix="$_OUT_DIR" \
    --libdir="$_OUT_DIR/lib" \
    --includedir="$_OUT_DIR/include" \
    --with-android-arch="$_ARCH" \
    --with-android-gcc="$_GPP_FULL" \
    --without-libraries="python"
    #--with-libraries="filesystem,system,iostreams,regex,math,date_time,???" 
  if ! [ $? -eq 0 ]; then exit 1; fi

  _PATH=$PATH
  export PATH="$_TOOLCHAIN_DIR/bin:$_TOOLCHAIN_DIR/$_TARGET/bin:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$PATH"
  _BOOST_TOOLSET="gcc-${_ARCH}"

  #if [ $_FORCE -eq 1 ]; then
    ./bjam clean \
      toolset="$_BOOST_TOOLSET" \
      target-os="android" \
      --prefix="$_OUT_DIR"
    if ! [ $? -eq 0 ]; then exit 1; fi
  #fi

  # tip: no cppflags
  _BOOST_CFLAGS="$_COMMON_CFLAGS $_CPPFLAGS_NDK_SYSROOT -fPIC  -Wno-long-long -Wno-unused -Wno-pedantic -Wno-missing-field-initializers -DBOOST_COROUTINE_NO_DEPRECATION_WARNING"
  _BOOST_LDFLAGS="$_COMMON_LDFLAGS $_LDFLAGS_NDK_SYSROOT"
  ./bjam install \
    toolset="$_BOOST_TOOLSET" \
    target-os="android" \
    cflags="$_BOOST_CFLAGS" \
    cxxflags="$_BOOST_CFLAGS" \
    linkflags="$_BOOST_LDFLAGS" \
    --prefix="$_OUT_DIR" \
    --disable-long-double -sNO_ZLIB=1 -sNO_BZIP2=1
  if ! [ $? -eq 0 ]; then exit 1; fi

  cd ..
  export PATH=$_PATH

  echo "*** boost has been compiled"
else
  echo "*** boost is already compiled"
fi
echo ""


########################### 6 - build iconv

if (! [ -f "${_OUT_DIR}/lib/libiconv.so" ]) || [ $_FORCE -eq 1 ]; then
  echo "*** Compiling libiconv..."

  # todo download https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.15.tar.gz

  cd libiconv # todo names
  _PATH=$PATH
  export PATH="$_TOOLCHAIN_DIR/bin:$_TOOLCHAIN_DIR/$_TARGET/bin:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$PATH"

  # tip: should be triplet host
  ./configure -q \
    --host="$_TARGET_3" \
    --target="$_TARGET_3" \
    --prefix="$_OUT_DIR" \
    --disable-shared \
    --enable-static \
    --with-pic \
    CXX="$_GPP_FULL" \
    CXXFLAGS="" \
    LDFLAGS="$_COMMON_CFLAGS $_LDFLAGS_NDK_SYSROOT $_LDFLAGS_OUT" \
    CPPFLAGS="$_COMMON_LDFLAGS $_CPPFLAGS_NDK_SYSROOT $_CPPFLAGS_OUT -DANDROID -fPIC " \
    LIBS="-lc -lm"

  #if [ $_FORCE -eq 1 ]; then
    make clean V=0 -s
    if ! [ $? -eq 0 ]; then exit 1; fi
  #fi
  if ! [ $? -eq 0 ]; then exit 1; fi
  make V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi
  make install V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi

  cd ..
  export PATH=$_PATH

  echo "*** libiconv has been compiled"
else
  echo "*** libiconv is already compiled"
fi
echo ""

export BOOST_LDFLAGS="$_LDFLAGS_OUT"
export BOOST_CPPFLAGS="$_CPPFLAGS_OUT"

########################### 7 - build mkvtoolnix

if ( ! [ -f "${_OUT_DIR}/mkvmerge" ]) || [ $_FORCE -eq 1 ]; then
  echo "*** Compiling mkvtoolnix..."

  # todo git https://github.com/mbunkus/mkvtoolnix

  cd mkvtoolnix # todo names
  _PATH=$PATH
  export PATH="$_TOOLCHAIN_DIR/bin:$_TOOLCHAIN_DIR/$_TARGET/bin:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$PATH"

  ./autogen.sh

  # https://github.com/nlohmann/json/issues/219
  _JSON_WORKAROUNDS=""
  # todo: need for arm64 ???
  if [ $_ARCH == "arm" ]; then
    _JSON_WORKAROUNDS="-DJSON_ANDROID_WORKAROUNDS"
  fi

  # tip: --host requires triplet
  # tip: -std=c++11 - won't work??? (tried for official NDK) (todo: try more)
  _LIBS="-lc -lm -lvorbis -logg -lebml -lmatroska"
  ./configure -q \
    --host="$_TARGET_3" \
    --target="$_TARGET_3" \
    --prefix="$_OUT_DIR" \
    --with-extra-includes="$_OUT_DIR/include\;$_NDK_SYSROOT/usr/include" \
    --with-extra-libs="$_OUT_DIR/lib\;$_NDK_SYSROOT/usr/lib" \
    CXX="$_GPP_FULL " \
    LD="$_LD_FULL" \
    CXXFLAGS="" \
    LDFLAGS="$_COMMON_CFLAGS $_LDFLAGS_NDK_SYSROOT $_LDFLAGS_OUT $_LDFLAGS_NDK_STL" \
    CPPFLAGS="$_COMMON_LDFLAGS $_JSON_WORKAROUNDS $_CPPFLAGS_NDK_SYSROOT $_CPPFLAGS_OUT $_CPPFLAGS_NDK_STL -DANDROID -DANDROID_STL=gnustl_static -Wno-type-limits" \
    LIBS="$_LIBS"

  # !!! пробую без -nostdlib - потом восстанови   ( -fPIC -> -fPIC -nostdlib )
  #todo stl (libc++/stlport/gnustl ???)
  #try -DANDROID_STL=c++_shared / -DANDROID_STL=gnustl_static
  #try -std=c++0x  -std=c++11
  #todo $_LDFLAGS_CRYSTALX  (и LIBS: -crystalx)
  #без -nostdlib пишет configure: error: Could not link against boost_system !   (но с -DANDROID_STL=gnustl_static не пишет)

#libs:
#disable shared library (.so) and enable only static library (.a)
#https://github.com/aria2/aria2/blob/master/android-config
#fpie vs fpic
#попробуй clang вместо gcc

  # ? попробуй вместо ./configure cxx=.. ld=..   сделать export cxx=..  expord ld=.. .... - неее, это справедливо для не-autoconf билда

#  /home/ukrbublik/projs/MkvMerger/app/jni/out_crx/armeabi-v7a/lib//libboost_regex.so: error: undefined reference to 'std::basic_string<wchar_t, std::char_traits<wchar_t>, std::allocator<wchar_t> >::~basic_string()'
# src/extract/libmtxextract.a(attachments.o)(.ARM.extab+0x0): error: undefined reference to '__gxx_personality_v0'
# src/extract/libmtxextract.a(chapters.o):chapters.cpp:function _GLOBAL__sub_I_chapters.cpp: error: undefined reference to 'std::ios_base::Init::Init()'
# src/extract/libmtxextract.a(cuesheets.o):cuesheets.cpp:function extract_cuesheet(std::string const&, kax_analyzer_c::parse_mode_e): error: undefined reference to 'libebml::EbmlMaster::~EbmlMaster()'
# src/output/libmtxoutput.a(p_vorbis.o):p_vorbis.cpp:function vorbis_packetizer_c::vorbis_packetizer_c(generic_reader_c*, track_info_c&, unsigned char*, int, unsigned char*, int, unsigned char*, int): error: undefined reference to '__cxa_free_exception'
# src/output/libmtxoutput.a(p_vorbis.o):p_vorbis.cpp:function vorbis_packetizer_c::vorbis_packetizer_c(generic_reader_c*, track_info_c&, unsigned char*, int, unsigned char*, int, unsigned char*, int): error: undefined reference to 'std::exception::~exception()'

# попробуй линкать с crystalx

  #if [ $_FORCE -eq 1 ]; then
    rake clean V=0 -s
    if ! [ $? -eq 0 ]; then exit 1; fi
  #fi
  if ! [ $? -eq 0 ]; then exit 1; fi
  rake V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi
exit 1;
  rake install V=0 -s
  if ! [ $? -eq 0 ]; then exit 1; fi

  cd ..
  export PATH=$_PATH

  echo "*** mkvtoolnix has been compiled"
else
  echo "*** mkvtoolnix is already compiled"
fi
echo ""
