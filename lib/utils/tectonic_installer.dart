import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart'; // May need for exec perms later

// Placeholder for actual Tectonic binary name for different architectures
// e.g., Map<String, String> tectonicBinaries = { 'arm64': 'tectonic_arm64', ... }
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
// Assuming NativeToolHelper will be created in lib/services/native_tool_helper.dart
import 'package:latex_editor/services/native_tool_helper.dart';


// Base name for the tool, platform-specific executables might have extensions
const String tectonicToolName = 'tectonic';
const String tectonicWindowsExe = 'tectonic.exe'; // Example for Windows

// Keys for shared_preferences
const String _prefsKeyTectonicPath = 'tectonic_executable_path_v2'; // Incremented version
const String _prefsKeyTectonicVersion = 'tectonic_bundled_version_v2';

// This version string should be updated if new binaries are bundled with the app.
// It forces re-extraction and permission setting if the bundled version changes.
const String currentBundledTectonicVersion = "0.15.0-bundle1"; // Example version

class TectonicInstaller {
  static Future<String?> getTectonicExecutablePath() async {
    // --- macOS: Check for bundled tool within the .app bundle ---
    if (Platform.isMacOS) {
      try {
        final mainAppExePath = Platform.resolvedExecutable; // e.g., YourApp.app/Contents/MacOS/YourAppName
        final macOSDir = File(mainAppExePath).parent;     // YourApp.app/Contents/MacOS/
        // Tools are expected to be alongside the main executable in Contents/MacOS/
        final toolPath = '${macOSDir.path}/$tectonicToolName';

        if (await File(toolPath).exists()) {
          print("TectonicInstaller (macOS): Found bundled in .app at $toolPath. Using direct path.");
          return toolPath;
        } else {
          // Alternative check: If tools are in Contents/Helpers/
          final helpersPath = '${macOSDir.parent.path}/Helpers/$tectonicToolName';
          if (await File(helpersPath).exists()) {
            print("TectonicInstaller (macOS): Found bundled in .app/Contents/Helpers/ at $helpersPath. Using direct path.");
            return helpersPath;
          }
          print("TectonicInstaller (macOS): Bundled tool not found in Contents/MacOS or Contents/Helpers. Will proceed to other methods.");
        }
      } catch (e) {
        print("TectonicInstaller (macOS): Error checking for bundled tool: $e. Will proceed to other methods.");
      }
    }

    // --- Windows: Check for bundled tool relative to main executable ---
    if (Platform.isWindows) {
      try {
        final mainAppExePath = Platform.resolvedExecutable;
        final mainAppDir = File(mainAppExePath).parent;
        final toolPath = '${mainAppDir.path}\\tools\\$tectonicWindowsExe';

        if (await File(toolPath).exists()) {
          print("TectonicInstaller (Windows): Found bundled at $toolPath. Using direct path.");
          return toolPath;
        } else {
          print("TectonicInstaller (Windows): Bundled tool not found at $toolPath. Will proceed to other methods.");
        }
      } catch (e) {
        print("TectonicInstaller (Windows): Error checking for bundled tool: $e. Will proceed to other methods.");
      }
    }

    // --- Linux AppImage: Check for bundled tool ---
    if (Platform.isLinux && Platform.environment.containsKey('APPIMAGE') && Platform.environment.containsKey('APPDIR')) {
      final appDir = Platform.environment['APPDIR'];
      final executablePath = '$appDir/usr/bin/$tectonicToolName';

      if (await File(executablePath).exists()) {
        print("TectonicInstaller (AppImage): Found at $executablePath. Using direct path.");
        return executablePath;
      } else {
        print("TectonicInstaller (AppImage): ERROR - Not found at AppImage path $executablePath. Fallback.");
        // Fall through to caching/extraction or PATH for AppImage if direct path fails
      }
    }

    // --- Caching/Extraction Logic (for other platforms or as fallback) ---
    final prefs = await SharedPreferences.getInstance();
    String? storedPath = prefs.getString(_prefsKeyTectonicPath);
    String? storedVersion = prefs.getString(_prefsKeyTectonicVersion);

    if (storedPath != null &&
        storedVersion == currentBundledTectonicVersion &&
        await File(storedPath).exists()) {
      print("TectonicInstaller: Using cached executable at $storedPath (Version: $storedVersion)");
      return storedPath;
    }

    print("TectonicInstaller: No valid cached executable or version mismatch (or not AppImage). Attempting to install from assets.");

    if (kIsWeb) {
      print("TectonicInstaller: Bundling not supported on web. Relying on PATH or server-side for Tectonic.");
      return tectonicToolName;
    }

    String platformDirName;
    String archDirName;
    String binaryFileName = tectonicToolName; // Default, override for Windows

    // Determine platform directory name
    if (Platform.isAndroid) platformDirName = 'android';
    else if (Platform.isIOS) platformDirName = 'ios';
    else if (Platform.isLinux) platformDirName = 'linux';
    else if (Platform.isMacOS) platformDirName = 'macos';
    else if (Platform.isWindows) {
      platformDirName = 'windows';
      binaryFileName = tectonicWindowsExe;
    } else {
      print("TectonicInstaller: Unsupported platform: ${Platform.operatingSystem}. Falling back to PATH.");
      return tectonicToolName;
    }

    // Determine architecture directory name (simplified - needs robust detection or build-time configuration)
    // This is a placeholder. Real implementation needs accurate architecture detection.
    // For Android, ABI splits in build process are preferred over runtime detection here for asset path.
    // For desktop, more specific detection or providing multiple and letting user choose/auto-detect might be needed.
    if (Platform.isAndroid) {
        // Example: assuming arm64-v8a. In reality, the app's specific ABI build would determine this.
        // The asset path must match the ABI-specific assets included.
        archDirName = 'arm64-v8a';
    } else if (Platform.isIOS) {
        archDirName = 'arm64'; // Device, simulator would be different
    } else if (Platform.isLinux) {
        // Could be 'x86_64' or 'aarch64'. Assuming x86_64 for now.
        archDirName = 'x86_64';
    } else if (Platform.isMacOS) {
        // Could be 'x86_64' or 'arm64'. Assuming arm64 for modern Macs.
        archDirName = 'arm64';
    } else if (Platform.isWindows) {
        archDirName = 'x86_64';
    } else {
        print("TectonicInstaller: Could not determine architecture for $platformDirName. Falling back to PATH.");
        return tectonicToolName;
    }

    final String assetPath = 'assets/bin/$platformDirName/$archDirName/$binaryFileName';
    print("TectonicInstaller: Target asset path: $assetPath");

    try {
      final ByteData byteData = await rootBundle.load(assetPath);
      final Directory appSupportDir = await getApplicationSupportDirectory();
      final Directory toolsDir = Directory('${appSupportDir.path}/bundled_tools/$tectonicToolName/$currentBundledTectonicVersion');

      // Ensure the specific versioned directory exists and is clean if we are re-extracting
      if (await toolsDir.exists() && storedVersion != currentBundledTectonicVersion) {
          print("TectonicInstaller: Clearing old version directory: ${toolsDir.path}");
          await toolsDir.delete(recursive: true);
      }
      await toolsDir.create(recursive: true);

      final File executableFile = File('${toolsDir.path}/$binaryFileName');

      await executableFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      print("TectonicInstaller: Copied binary to ${executableFile.path}");

      bool permissionsSet = false;
      if (Platform.isAndroid || Platform.isIOS || Platform.isLinux || Platform.isMacOS) {
        print("TectonicInstaller: Attempting to set execute permission via NativeToolHelper...");
        permissionsSet = await NativeToolHelper.setExecutablePermission(executableFile.path);
        if (permissionsSet) {
          print("TectonicInstaller: Execute permission successfully set for ${executableFile.path}");
        } else {
          print("TectonicInstaller: Failed to set execute permission for ${executableFile.path} via platform channel.");
        }
      } else if (Platform.isWindows) {
        // .exe files are generally executable by default on Windows.
        permissionsSet = true;
        print("TectonicInstaller: Assuming executable on Windows: ${executableFile.path}");
      }

      if (permissionsSet) {
        await prefs.setString(_prefsKeyTectonicPath, executableFile.path);
        await prefs.setString(_prefsKeyTectonicVersion, currentBundledTectonicVersion);
        print("TectonicInstaller: Successfully prepared. Path cached: ${executableFile.path}");
        return executableFile.path;
      } else {
        print("TectonicInstaller: Failed to ensure execute permissions. Falling back to PATH.");
        // Optionally, delete the copied file if permissions couldn't be set and it's unusable
        // await executableFile.delete();
        return tectonicToolName;
      }
    } on FlutterException catch (e) {
        // This catches errors like asset not found
        print("TectonicInstaller: FlutterException (likely asset not found at $assetPath): $e. Falling back to PATH.");
        return tectonicToolName;
    }
    catch (e) {
      print("TectonicInstaller: Error during binary preparation ($assetPath): $e. Falling back to PATH.");
      return tectonicToolName;
    }
  }
}
