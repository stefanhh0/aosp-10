#!/bin/bash
set -e

# ----------------------------------------------------------------------
# Variables have to be adjusted accordingly
# ----------------------------------------------------------------------
SOURCE=~/android/source
APK=~/android/q
LUNCH_CHOICE=aosp_g8441-userdebug
PLATFORM=yoshino
DEVICE=lilac
# ----------------------------------------------------------------------

pick_pr() {
    local REMOTE=$1
    local PR_ID=$2
    local COMMITS=$3
    local INDEX=$(($COMMITS - 1))

    git fetch $REMOTE pull/$PR_ID/head

    while [ $INDEX -ge 0 ]; do
        git cherry-pick -Xtheirs --no-edit FETCH_HEAD~$INDEX
        INDEX=$(($INDEX - 1))
    done
}

cd $SOURCE

ANDROID_VERSION=`cat .repo/manifest.xml|grep default\ revision|sed 's#^.*refs/tags/\(.*\)"#\1#1'`

if [ -d kernel/sony/msm-4.9 ]; then
   rm -r kernel/sony/msm-4.9
fi

if [ -d hardware/qcom/sdm845 ]; then
    rm -r hardware/qcom/sdm845
fi

if [ -d device/sony/customization/ ]; then
    rm -r device/sony/customization
fi

for path in \
device/sony/common \
device/sony/sepolicy \
device/sony/$PLATFORM \
kernel/sony/msm-4.14/common-kernel \
vendor/opengapps/sources/all \
vendor/opengapps/sources/arm \
vendor/opengapps/sources/arm64 \
vendor/oss/transpower
do
    if [ -d $path ]; then
        pushd $path
            git clean -d -f -e "*dtb*"
            git reset --hard m/$ANDROID_VERSION
        popd
    fi
done

# ----------------------------------------------------------------------
# Manifest adjustments
# ----------------------------------------------------------------------
pushd .repo/manifests
    git clean -d -f
    git checkout .
    git pull

    # ----------------------------------------------------------------------
    # Include opengapps repos
    # ----------------------------------------------------------------------
    patch -p1 <<EOF
diff --git a/default.xml b/default.xml
index 18983252..134ba366 100644
--- a/default.xml
+++ b/default.xml
@@ -768,4 +768,16 @@

   <repo-hooks in-project="platform/tools/repohooks" enabled-list="pre-upload" />

+  <remote name="opengapps" fetch="https://github.com/MarijnS95/"  />
+  <!--<remote name="opengapps" fetch="https://github.com/opengapps/"  />-->
+  <remote name="gitlab" fetch="https://gitlab.opengapps.org/opengapps/"  />
+
+  <project path="vendor/opengapps/build" name="opengapps_aosp_build" revision="master" remote="opengapps" />
+  <!--<project path="vendor/opengapps/build" name="aosp_build" revision="master" remote="opengapps" />-->
+
+  <project path="vendor/opengapps/sources/all" name="all" clone-depth="1" revision="master" remote="gitlab" />
+
+  <!-- arm64 depends on arm -->
+  <project path="vendor/opengapps/sources/arm" name="arm" clone-depth="1" revision="master" remote="gitlab" />
+  <project path="vendor/opengapps/sources/arm64" name="arm64" clone-depth="1" revision="master" remote="gitlab" />
 </manifest>
EOF
popd

# ----------------------------------------------------------------------
# Local manifest adjustments
# ----------------------------------------------------------------------
pushd .repo/local_manifests
    git clean -d -f
    git fetch
    git reset --hard origin/$ANDROID_VERSION
popd

./repo_update.sh

pushd device/sony/common
    git fetch https://github.com/MarijnS95/device-sony-common
    # common-packages: Include default thermal hw module.
    git cherry-pick --no-edit d74ebb45e1783fdd1e757faa2abcb626b34489f5
popd

pushd device/sony/sepolicy
    git fetch https://github.com/MarijnS95/device-sony-sepolicy
    # WIP: Copy hal_thermal_default from crosshatch.
    git cherry-pick --no-edit 2974bc6a5497c945a72df3882bc032aa741ce443
popd

# ----------------------------------------------------------------------
# Pull opengapps large files that are stored in git lfs
# ----------------------------------------------------------------------
for path in \
vendor/opengapps/sources/all \
vendor/opengapps/sources/arm \
vendor/opengapps/sources/arm64
do
    pushd $path
        git lfs pull &
    popd
done
wait

# ----------------------------------------------------------------------
# opengapps permissions-google
# ----------------------------------------------------------------------
pushd vendor/opengapps/sources/all
    patch -p1 <<EOF
diff --git a/etc/permissions/privapp-permissions-google.xml b/etc/permissions/privapp-permissions-google.xml
index 0b46f07..2d2e5cd 100644
--- a/etc/permissions/privapp-permissions-google.xml
+++ b/etc/permissions/privapp-permissions-google.xml
@@ -81,12 +81,14 @@ It allows additional grants on top of privapp-permissions-platform.xml
         <permission name="android.permission.MANAGE_USERS"/>
         <permission name="android.permission.PACKAGE_USAGE_STATS"/>
         <permission name="android.permission.PACKAGE_VERIFICATION_AGENT"/>
+        <permission name="android.permission.READ_PRIVILEGED_PHONE_STATE"/>
         <permission name="android.permission.READ_RUNTIME_PROFILES"/>
         <permission name="android.permission.REAL_GET_TASKS"/>
-        <permission name="android.permission.READ_PRIVILEGED_PHONE_STATE" />
-        <permission name="android.permission.REBOOT" />
+        <permission name="android.permission.REBOOT"/>
+        <permission name="android.permission.SEND_DEVICE_CUSTOMIZATION_READY"/>
         <permission name="android.permission.SEND_SMS_NO_CONFIRMATION"/>
         <permission name="android.permission.SET_PREFERRED_APPLICATIONS"/>
+        <permission name="android.permission.START_ACTIVITIES_FROM_BACKGROUND"/>
         <permission name="android.permission.STATUS_BAR"/>
         <permission name="android.permission.SUBSTITUTE_NOTIFICATION_APP_NAME"/>
         <permission name="android.permission.UPDATE_DEVICE_STATS"/>
@@ -297,6 +299,7 @@ It allows additional grants on top of privapp-permissions-platform.xml
         <permission name="android.permission.CONNECTIVITY_USE_RESTRICTED_NETWORKS"/>
         <permission name="android.permission.CONTROL_INCALL_EXPERIENCE"/>
         <permission name="android.permission.CONTROL_DISPLAY_SATURATION"/>
+        <permission name="android.permission.CONTROL_KEYGUARD_SECURE_NOTIFICATIONS"/>
         <permission name="android.permission.DISPATCH_PROVISIONING_MESSAGE"/>
         <permission name="android.permission.DUMP"/>
         <permission name="android.permission.GET_APP_OPS_STATS"/>
@@ -305,7 +308,7 @@ It allows additional grants on top of privapp-permissions-platform.xml
         <permission name="android.permission.INVOKE_CARRIER_SETUP"/>
         <permission name="android.permission.LOCAL_MAC_ADDRESS"/>
         <permission name="android.permission.LOCATION_HARDWARE"/>
-        <permission name="android.permission.MANAGE_ACTIVITY_STACKS"/>
+        <permission name="android.permission.LOCK_DEVICE"/>
         <permission name="android.permission.MANAGE_DEVICE_ADMINS"/>
         <permission name="android.permission.MANAGE_SOUND_TRIGGER"/>
         <permission name="android.permission.MANAGE_SUBSCRIPTION_PLANS"/>
@@ -331,12 +334,16 @@ It allows additional grants on top of privapp-permissions-platform.xml
         <permission name="android.permission.RECOVER_KEYSTORE"/>
         <permission name="android.permission.RECOVERY"/>
         <permission name="android.permission.REGISTER_CALL_PROVIDER"/>
+        <permission name="android.permission.REMOTE_DISPLAY_PROVIDER"/>
+        <permission name="android.permission.RESET_PASSWORD"/>
         <permission name="android.permission.SCORE_NETWORKS"/>
         <permission name="android.permission.SEND_SMS_NO_CONFIRMATION"/>
         <permission name="android.permission.SET_TIME"/>
         <permission name="android.permission.SET_TIME_ZONE"/>
+        <permission name="android.permission.START_ACTIVITIES_FROM_BACKGROUND"/>
         <permission name="android.permission.START_TASKS_FROM_RECENTS"/>
         <permission name="android.permission.SUBSTITUTE_NOTIFICATION_APP_NAME"/>
+        <permission name="android.permission.SUBSTITUTE_SHARE_TARGET_APP_NAME_AND_ICON"/>
         <permission name="android.permission.TETHER_PRIVILEGED"/>
         <permission name="android.permission.UPDATE_APP_OPS_STATS"/>
         <permission name="android.permission.USE_RESERVED_DISK"/>
@@ -437,14 +444,25 @@ It allows additional grants on top of privapp-permissions-platform.xml
         <permission name="android.permission.CHANGE_COMPONENT_ENABLED_STATE"/>
     </privapp-permissions>

+    <privapp-permissions package="com.google.android.permissioncontroller">
+        <permission name="android.permission.MANAGE_USERS"/>
+        <permission name="android.permission.OBSERVE_GRANT_REVOKE_PERMISSIONS"/>
+        <permission name="android.permission.GET_APP_OPS_STATS"/>
+        <permission name="android.permission.UPDATE_APP_OPS_STATS"/>
+        <permission name="android.permission.REQUEST_INCIDENT_REPORT_APPROVAL"/>
+        <permission name="android.permission.APPROVE_INCIDENT_REPORTS"/>
+        <permission name="android.permission.READ_PRIVILEGED_PHONE_STATE" />
+        <permission name="android.permission.SUBSTITUTE_NOTIFICATION_APP_NAME" />
+    </privapp-permissions>
+
     <privapp-permissions package="com.google.android.packageinstaller">
-        <permission name="android.permission.CLEAR_APP_CACHE"/>
         <permission name="android.permission.DELETE_PACKAGES"/>
         <permission name="android.permission.INSTALL_PACKAGES"/>
+        <permission name="android.permission.USE_RESERVED_DISK"/>
         <permission name="android.permission.MANAGE_USERS"/>
-        <permission name="android.permission.OBSERVE_GRANT_REVOKE_PERMISSIONS"/>
         <permission name="android.permission.UPDATE_APP_OPS_STATS"/>
-        <permission name="android.permission.USE_RESERVED_DISK"/>
+        <permission name="android.permission.SUBSTITUTE_NOTIFICATION_APP_NAME"/>
+        <permission name="android.permission.PACKAGE_USAGE_STATS"/>
     </privapp-permissions>

     <privapp-permissions package="com.google.android.partnersetup">
@@ -488,11 +506,12 @@ It allows additional grants on top of privapp-permissions-platform.xml
         <permission name="android.permission.PERFORM_CDMA_PROVISIONING"/>
         <permission name="android.permission.READ_PRIVILEGED_PHONE_STATE"/>
         <permission name="android.permission.REBOOT"/>
-        <permission name="android.permission.REQUEST_NETWORK_SCORES"/>
         <permission name="android.permission.SET_TIME"/>
         <permission name="android.permission.SET_TIME_ZONE"/>
         <permission name="android.permission.SHUTDOWN"/>
         <permission name="android.permission.STATUS_BAR"/>
+        <permission name="android.permission.START_ACTIVITIES_FROM_BACKGROUND"/>
+        <permission name="android.permission.SUBSTITUTE_NOTIFICATION_APP_NAME"/>
         <permission name="android.permission.WRITE_APN_SETTINGS"/>
         <permission name="android.permission.WRITE_SECURE_SETTINGS"/>
     </privapp-permissions>
@@ -576,11 +596,15 @@ It allows additional grants on top of privapp-permissions-platform.xml
     </privapp-permissions>

     <privapp-permissions package="com.google.android.apps.wellbeing">
+        <permission name="android.permission.ACCESS_INSTANT_APPS"/>
+        <permission name="android.permission.CONTROL_DISPLAY_COLOR_TRANSFORMS"/>
         <permission name="android.permission.CONTROL_DISPLAY_SATURATION"/>
+        <permission name="android.permission.INTERACT_ACROSS_PROFILES"/>
         <permission name="android.permission.LOCATION_HARDWARE"/>
         <permission name="android.permission.MODIFY_PHONE_STATE"/>
         <permission name="android.permission.OBSERVE_APP_USAGE"/>
         <permission name="android.permission.PACKAGE_USAGE_STATS"/>
+        <permission name="android.permission.START_ACTIVITIES_FROM_BACKGROUND"/>
         <permission name="android.permission.SUBSTITUTE_NOTIFICATION_APP_NAME"/>
         <permission name="android.permission.SUSPEND_APPS"/>
         <permission name="android.permission.WRITE_SECURE_SETTINGS"/>
EOF
popd

# ----------------------------------------------------------------------
# customization to build opengapps
# ----------------------------------------------------------------------
mkdir device/sony/customization
cat >device/sony/customization/customization.mk <<EOF
GAPPS_VARIANT := pico

GAPPS_PRODUCT_PACKAGES += \\
    Chrome \\
    GooglePackageInstaller \\
    GooglePermissionController \\
    SetupWizard

WITH_DEXPREOPT := true

GAPPS_FORCE_WEBVIEW_OVERRIDES := true
GAPPS_FORCE_BROWSER_OVERRIDES := true

\$(call inherit-product, vendor/opengapps/build/opengapps-packages.mk)
EOF

# ----------------------------------------------------------------------
# Copy required apks for android 10 that are not yet in opengapps.
# The apks can be obtained from:
# https://developers.google.com/android/images
#
# The apks used here are downloaded via extract-apks.sh
#
# If using a different image, version numbers might be different and
# have to be adjusted using the versionCode from the command:
# aapt dump badging <name>.apk |grep versionCode
# ----------------------------------------------------------------------
# PackageInstaller
# ----------------------------------------------------------------------
mkdir -p vendor/opengapps/sources/all/priv-app/com.google.android.packageinstaller/29/nodpi
cp $APK/GooglePackageInstaller.apk vendor/opengapps/sources/all/priv-app/com.google.android.packageinstaller/29/nodpi/29.apk

# ----------------------------------------------------------------------
# PermissionController
# ----------------------------------------------------------------------
mkdir -p vendor/opengapps/sources/arm64/app/com.google.android.permissioncontroller/29/nodpi
cp $APK/GooglePermissionControllerPrebuilt.apk vendor/opengapps/sources/arm64/app/com.google.android.permissioncontroller/29/nodpi/291900200.apk

# ----------------------------------------------------------------------
# SetupWizard
# ----------------------------------------------------------------------
mkdir -p vendor/opengapps/sources/all/priv-app/com.google.android.setupwizard.default/29/nodpi
cp $APK/SetupWizardPrebuilt.apk vendor/opengapps/sources/all/priv-app/com.google.android.setupwizard.default/29/nodpi/2842.apk

# ----------------------------------------------------------------------
# TrichromeLibrary
# ----------------------------------------------------------------------
mkdir -p vendor/opengapps/sources/all/app/com.google.android.trichromelibrary/29/nodpi
cp $APK/TrichromeLibrary.apk vendor/opengapps/sources/all/app/com.google.android.trichromelibrary/29/nodpi/373018658.apk

. build/envsetup.sh
lunch $LUNCH_CHOICE

make clean

pushd kernel/sony/msm-4.14/common-kernel
    PLATFORM_UPPER=`echo $PLATFORM|tr '[:lower:]' '[:upper:]'`
    sed -i "s/PLATFORMS=.*/PLATFORMS=$PLATFORM/1" build-kernels-gcc.sh
    sed -i "s/$PLATFORM_UPPER=.*/$PLATFORM_UPPER=$DEVICE/1" build-kernels-gcc.sh
    find . -name "*dtb*" -exec rm "{}" \;
    bash ./build-kernels-gcc.sh
popd

make -j`nproc --all`
