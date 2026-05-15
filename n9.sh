#!/bin/bash
set -e

PROJECT_PATH=""
DEVICE_IP="192.168.3.15"
DEVICE_USER="developer"
BUILD_TYPE="debug"

SSH_OPTS="-i ~/.ssh/id_rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa"


function build() {
    echo "Building project at $PROJECT_PATH..."

    PRO_FILE=$(find "$PROJECT_PATH" -maxdepth 1 -name "*.pro" | head -1)
    if [ -z "$PRO_FILE" ]; then
        echo "No .pro file found in $PROJECT_PATH"
        exit 1
    fi

    PROJECT_NAME=$(basename "$PRO_FILE" .pro)

    cd "$PROJECT_PATH"

    # Clean previous build
    /opt/QtSDK/Madde/bin/mad -t harmattan_10.2011.34-1_rt1.2 make clean 2>/dev/null || true
    rm -rf debian

    # Run qmake with explicit compiler settings
    /opt/QtSDK/Madde/bin/mad -t harmattan_10.2011.34-1_rt1.2 qmake \
        "$PRO_FILE" \
        -r -spec linux-g++-maemo \
        CONFIG+=$BUILD_TYPE \
        QMAKE_CXX=/opt/QtSDK/Madde/targets/harmattan_10.2011.34-1_rt1.2/bin/g++ \
        QMAKE_CC=/opt/QtSDK/Madde/targets/harmattan_10.2011.34-1_rt1.2/bin/gcc

    # Build
    /opt/QtSDK/Madde/bin/mad -t harmattan_10.2011.34-1_rt1.2 make -j4

    # Copy debian files from qtc_packaging
    if [ -d "qtc_packaging/debian_harmattan" ]; then
        cp -r qtc_packaging/debian_harmattan debian
        chmod +x debian/rules
    fi

    # Create debian package if debian directory exists
    if [ -d "debian" ]; then
        /opt/QtSDK/Madde/bin/mad dpkg-buildpackage -nc -uc -us

        # Find the version from changelog
        VERSION=$(head -1 debian/changelog | sed 's/.*(\(.*\)).*/\1/')
        DEB_FILE="../${PROJECT_NAME}_${VERSION}_armel.deb"

        # Copy build artifacts to build directory in project
        mkdir -p build
        cp "$DEB_FILE" build/ 2>/dev/null || true
        cp "$PROJECT_NAME" build/ 2>/dev/null || true

        echo "Build complete! Package: build/$(basename $DEB_FILE)"
    else
        echo "No debian directory - binary only build"
        mkdir -p build
        cp "$PROJECT_NAME" build/ 2>/dev/null || true
    fi
}

function run() {
    build

    PROJECT_NAME=$(basename "$(find "$PROJECT_PATH" -name "*.pro" | head -1)" .pro)

    # Find the .deb file in build directory
    DEB_FILE=$(find "$PROJECT_PATH/build" -name "*.deb" | head -1)

    if [ -z "$DEB_FILE" ]; then
        echo "No .deb package found in build/"
        exit 1
    fi

    echo "Deploying to $DEVICE_USER@$DEVICE_IP..."

    # Copy and install (remove $SCP_OPTS)
    scp $SSH_OPTS "$DEB_FILE" $DEVICE_USER@$DEVICE_IP:/tmp/
    ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "dpkg -i /tmp/$(basename $DEB_FILE)"

    # Run the application
    echo "Starting $PROJECT_NAME..."
    ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "/opt/$PROJECT_NAME/bin/$PROJECT_NAME"
}

COMMAND=$1
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --path)
            PROJECT_PATH="$2"
            shift 2
            ;;
        --device)
            DEVICE_IP="$2"
            shift 2
            ;;
        --release)
            BUILD_TYPE="release"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done


case $COMMAND in
    build|run)
        if [ -z "$PROJECT_PATH" ]; then
            echo "Error: --path is required"
            exit 1
        fi
        $COMMAND
        ;;
    setup)
        setup
        ;;
    *)
        echo "Usage: n9 [build|run|setup] --path <project> [--device <ip>] [--release]"
        exit 1
        ;;
esac
