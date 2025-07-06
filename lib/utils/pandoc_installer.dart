import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle, FlutterException;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latex_editor/services/native_tool_helper.dart'; // Assuming this path

const String pandocToolName = 'pandoc';
const String pandocWindowsExe = 'pandoc.exe';

const String _prefsKeyPandocPath = 'pandoc_executable_path_v2'; // Ensure key versioning
const String _prefsKeyPandocVersion = 'pandoc_bundled_version_v2';

// This version string should be updated if new Pandoc binaries are bundled.
const String currentBundledPandocVersion = "3.7.0.2-bundle1"; // Example version, align with actual bundled binary

class PandocInstaller {
  static Future<String?> getPandocExecutablePath() async {
    // --- Windows: Check for bundled tool relative to main executable ---
    if (Platform.isWindows) {
      try {
        final mainAppExePath = Platform.resolvedExecutable;
        final mainAppDir = File(mainAppExePath).parent;
        final toolPath = '${mainAppDir.path}\\tools\\$pandocWindowsExe';

        if (await File(toolPath).exists()) {
          print("PandocInstaller (Windows): Found bundled at $toolPath. Using direct path.");
          return toolPath;
        } else {
          print("PandocInstaller (Windows): Bundled tool not found at $toolPath. Will proceed to other methods.");
        }
      } catch (e) {
        print("PandocInstaller (Windows): Error checking for bundled tool: $e. Will proceed to other methods.");
      }
    }

    // --- Linux AppImage: Check for bundled tool ---
    if (Platform.isLinux && Platform.environment.containsKey('APPIMAGE') && Platform.environment.containsKey('APPDIR')) {
      final appDir = Platform.environment['APPDIR'];
      final executablePath = '$appDir/usr/bin/$pandocToolName'; // pandocToolName is 'pandoc'

      if (await File(executablePath).exists()) {
        print("PandocInstaller (AppImage): Found at $executablePath. Using direct path.");
        return executablePath;
      } else {
        print("PandocInstaller (AppImage): ERROR - Not found at AppImage path $executablePath. Fallback.");
        // Fall through to caching/extraction or PATH
      }
    }

    // --- Caching/Extraction Logic (for other platforms or as fallback) ---
    final prefs = await SharedPreferences.getInstance();
    String? storedPath = prefs.getString(_prefsKeyPandocPath);
    String? storedVersion = prefs.getString(_prefsKeyPandocVersion);

    if (storedPath != null &&
        storedVersion == currentBundledPandocVersion &&
        await File(storedPath).exists()) {
      print("PandocInstaller: Using cached executable at $storedPath (Version: $storedVersion)");
      return storedPath;
    }

    print("PandocInstaller: No valid cached executable or version mismatch (or not AppImage). Attempting to install from assets.");

    if (kIsWeb) {
      print("PandocInstaller: Bundling not supported on web. Relying on PATH or server-side for Pandoc.");
      return pandocToolName;
    }

    String platformDirName;
    String archDirName;
    String binaryFileName = pandocToolName; // Default, override for Windows

    if (Platform.isAndroid) platformDirName = 'android';
    else if (Platform.isIOS) platformDirName = 'ios';
    else if (Platform.isLinux) platformDirName = 'linux';
    else if (Platform.isMacOS) platformDirName = 'macos';
    else if (Platform.isWindows) {
      platformDirName = 'windows';
      binaryFileName = pandocWindowsExe;
    } else {
      print("PandocInstaller: Unsupported platform: ${Platform.operatingSystem}. Falling back to PATH.");
      return pandocToolName;
    }

    // Simplified architecture detection placeholder - needs robust solution or build-time config.
    if (Platform.isAndroid) archDirName = 'arm64-v8a'; // Example, align with actual bundled ABI
    else if (Platform.isIOS) archDirName = 'arm64'; // Device
    else if (Platform.isLinux) archDirName = 'x86_64'; // Common default
    else if (Platform.isMacOS) archDirName = 'arm64'; // Modern Macs
    else if (Platform.isWindows) archDirName = 'x86_64';
    else {
      print("PandocInstaller: Could not determine architecture for $platformDirName. Falling back to PATH.");
      return pandocToolName;
    }

    final String assetPath = 'assets/bin/$platformDirName/$archDirName/$binaryFileName';
    print("PandocInstaller: Target asset path: $assetPath");

    try {
      final ByteData byteData = await rootBundle.load(assetPath);
      final Directory appSupportDir = await getApplicationSupportDirectory();
      // Ensure versioned directory for tool to allow updates/re-extraction
      final Directory toolsDir = Directory('${appSupportDir.path}/bundled_tools/$pandocToolName/$currentBundledPandocVersion');

      if (await toolsDir.exists() && storedVersion != currentBundledPandocVersion) {
        print("PandocInstaller: Clearing old version directory: ${toolsDir.path}");
        await toolsDir.delete(recursive: true);
      }
      await toolsDir.create(recursive: true);

      final File executableFile = File('${toolsDir.path}/$binaryFileName');

      await executableFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      print("PandocInstaller: Copied binary to ${executableFile.path}");

      bool permissionsSet = false;
      if (Platform.isAndroid || Platform.isIOS || Platform.isLinux || Platform.isMacOS) {
        print("PandocInstaller: Attempting to set execute permission via NativeToolHelper for ${executableFile.path}...");
        permissionsSet = await NativeToolHelper.setExecutablePermission(executableFile.path);
        if (permissionsSet) {
          print("PandocInstaller: Execute permission successfully set for ${executableFile.path}");
        } else {
          print("PandocInstaller: Failed to set execute permission for ${executableFile.path} via platform channel.");
        }
      } else if (Platform.isWindows) {
        permissionsSet = true; // .exe files are generally executable
        print("PandocInstaller: Assuming executable on Windows: ${executableFile.path}");
      }

      if (permissionsSet) {
        await prefs.setString(_prefsKeyPandocPath, executableFile.path);
        await prefs.setString(_prefsKeyPandocVersion, currentBundledPandocVersion);
        print("PandocInstaller: Successfully prepared. Path cached: ${executableFile.path}");
        return executableFile.path;
      } else {
        print("PandocInstaller: Failed to ensure execute permissions. Falling back to PATH.");
        return pandocToolName;
      }
    } on FlutterException catch (e) {
        // This catches errors like asset not found
        print("PandocInstaller: FlutterException (likely asset not found at $assetPath): $e. Falling back to PATH.");
        return pandocToolName;
    }
    catch (e) {
      print("PandocInstaller: Error during binary preparation ($assetPath): $e. Falling back to PATH.");
      return pandocToolName;
    }
  }
}
