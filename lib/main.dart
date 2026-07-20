import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'screens/root_shell.dart';
import 'theme/semantic/light.dart';
import 'theme/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const JunaidZaidiLibraryApp());
}

/// App root: mirrors app/_layout.js (ThemeProvider + Stack) plus
/// app/(tabs)/_layout.js's tab bar, combined into one shell since Flutter
/// doesn't split "root layout" and "tab layout" into separate files the
/// way expo-router does.
///
/// NOTE: `home` still points straight at RootShell. Phase 2 swaps this to
/// AuthGate, which will decide between the auth flow and RootShell based
/// on whether a Koha session exists. Left as RootShell here so Phase 1
/// stays runnable on its own — Firebase now initializes on launch,
/// nothing else changes yet.
class JunaidZaidiLibraryApp extends StatelessWidget {
  const JunaidZaidiLibraryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppThemeProvider(
      child: MaterialApp(
        title: 'Junaid Zaidi Library',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: lightColors.background.primary,
          splashFactory: NoSplash.splashFactory,
          appBarTheme: AppBarTheme(
            backgroundColor: lightColors.background.primary,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: lightColors.text.primary,
            iconTheme: IconThemeData(color: lightColors.text.primary),
            titleTextStyle: AppTypography.h5
                .toTextStyle(color: lightColors.text.primary)
                .copyWith(fontSize: AppTypography.bodyLarge.fontSize),
          ),
        ),
        home: const RootShell(),
      ),
    );
  }
}