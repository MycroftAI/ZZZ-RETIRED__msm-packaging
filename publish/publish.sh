#!/usr/bin/env bash

# fail on all errors
set -Ee

TOP=$(cd $(dirname $0)/.. && pwd -L)
BUILD_DIR=${TOP}/build
DIST_DIR=${TOP}/dist
ARCH="$(dpkg --print-architecture)"

rm -rf ${TOP}/msm
rm -rf ${TOP}/build
rm -rf ${TOP}/dist

if [ "$1" = "-q" ]; then
  QUIET="echo"
fi

function _run() {
  if [[ "$QUIET" ]]; then
    echo "$*"
  else
    eval "$@"
  fi
}

MSM_ARTIFACT_BASE="msm-${ARCH}_${VERSION}"

mkdir -p ${TOP}/build
mkdir -p ${TOP}/dist
pushd ${TOP}/build
git clone https://github.com/MycroftAI/msm.git .
VERSION="$(basename $(git describe --abbrev=0 --tags) | sed -e 's/v//g')"
git checkout tags/release/v${VERSION}
popd

function replace() {
  local FILE=$1
  local PATTERN=$2
  local VALUE=$3
  local TMP_FILE="/tmp/$$.replace"
  cat ${FILE} | sed -e "s/${PATTERN}/${VALUE}/g" > ${TMP_FILE}
  mv ${TMP_FILE} ${FILE}
}


DEB_BASE="msm-${ARCH}_${VERSION}-1"
DEB_DIR=${TOP}/build/${DEB_BASE}
mkdir -p ${DEB_DIR}/DEBIAN
mkdir -p ${DEB_DIR}/usr/local/bin
cp -rfv ${TOP}/build/msm ${DEB_DIR}/usr/local/bin

echo "Creating debian control file"
# setup control file
CONTROL_FILE=${DEB_DIR}/DEBIAN/control
cp ${TOP}/publish/deb_base/control.template ${CONTROL_FILE}
replace ${CONTROL_FILE} "%%PACKAGE%%" "msm"
replace ${CONTROL_FILE} "%%VERSION%%" "${VERSION}"
replace ${CONTROL_FILE} "%%ARCHITECTURE%%" "${ARCH}"
replace ${CONTROL_FILE} "%%DESCRIPTION%%" "msm"
#replace ${CONTROL_FILE} "%%PRE_DEPENDS%%" ""

echo "Creating debian preinst file"
PREINST_FILE=${DEB_DIR}/DEBIAN/preinst
cp ${TOP}/publish/deb_base/preinst.template ${PREINST_FILE}
replace ${PREINST_FILE} "%%INSTALL_USER%%" "mycroft"
chmod 0755 ${PREINST_FILE}

echo "Creating debian postinst file"
POSTINST_FILE=${DEB_DIR}/DEBIAN/postinst
cp ${TOP}/publish/deb_base/postinst.template ${POSTINST_FILE}
replace ${POSTINST_FILE} "%%INSTALL_USER%%" "mycroft"
chmod 0755 ${POSTINST_FILE}

echo "Creating debian prerm file"
PRERM_FILE=${DEB_DIR}/DEBIAN/prerm
cp ${TOP}/publish/deb_base/prerm.template ${PRERM_FILE}
#replace ${PRERM_FILE} "%%INSTALL_USER%%" "mycroft"
chmod 0755 ${PRERM_FILE}

echo "Creating debian postrm file"
POSTRM_FILE=${DEB_DIR}/DEBIAN/postrm
cp ${TOP}/publish/deb_base/postrm.template ${POSTRM_FILE}
replace ${POSTRM_FILE} "%%INSTALL_USER%%" "mycroft"
chmod 0755 ${POSTRM_FILE}


pushd $(dirname ${DEB_DIR})
dpkg-deb --build ${DEB_BASE}
mv *.deb ${TOP}/dist
popd

cd ${TOP}/dist
_run s3cmd -c ${HOME}/.s3cfg.mycroft-artifact-writer sync --acl-public . s3://bootstrap.mycroft.ai/artifacts/apt/${ARCH}/msm/${VERSION}/
echo ${VERSION} > latest
_run s3cmd -c ${HOME}/.s3cfg.mycroft-artifact-writer put --acl-public ${TOP}/dist/latest s3://bootstrap.mycroft.ai/artifacts/apt/${ARCH}/msm/
