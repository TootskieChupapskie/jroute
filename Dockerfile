# Dockerfile for building Flutter Android APK
FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    FLUTTER_HOME=/opt/flutter \
    FLUTTER_VERSION=3.24.0 \
    PATH="/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:${PATH}"

# Install all dependencies, Android SDK, and Flutter in one layer
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    openjdk-17-jdk \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    # Install Android SDK
    && mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools \
    && cd ${ANDROID_SDK_ROOT}/cmdline-tools \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip \
    && unzip -q commandlinetools-linux-9477386_latest.zip \
    && rm commandlinetools-linux-9477386_latest.zip \
    && mv cmdline-tools latest \
    # Accept licenses and install SDK packages
    && yes | sdkmanager --licenses \
    && sdkmanager "platform-tools" "platforms;android-33" "build-tools;33.0.0" \
    # Install Flutter
    && cd /opt \
    && wget -q https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
    && tar xf flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
    && rm flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
    && flutter precache --android \
    && flutter doctor -v

# Set working directory
WORKDIR /app

# Copy only dependency files first (for caching)
COPY pubspec.yaml pubspec.lock ./

# Get Flutter dependencies
RUN flutter pub get

# Copy the rest of the project
COPY . .

# Build Android APK
CMD ["flutter", "build", "apk", "--release"]
