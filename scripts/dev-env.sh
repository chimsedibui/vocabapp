# Source this file in WSL: source scripts/dev-env.sh
# Installed SDKs are user-local; do not source this in native Windows.
export FLUTTER_ROOT="$HOME/.local/opt/flutter"
export JAVA_HOME="$HOME/.local/opt/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
case ":$PATH:" in *":$FLUTTER_ROOT/bin:"*) ;; *) export PATH="$FLUTTER_ROOT/bin:$PATH" ;; esac
case ":$PATH:" in *":$JAVA_HOME/bin:"*) ;; *) export PATH="$JAVA_HOME/bin:$PATH" ;; esac
case ":$PATH:" in *":$ANDROID_HOME/cmdline-tools/latest/bin:"*) ;; *) export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH" ;; esac
case ":$PATH:" in *":$ANDROID_HOME/platform-tools:"*) ;; *) export PATH="$ANDROID_HOME/platform-tools:$PATH" ;; esac
