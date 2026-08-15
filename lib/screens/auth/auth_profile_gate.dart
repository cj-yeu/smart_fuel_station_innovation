import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../../services/profile_service.dart';
import '../home/home_screen.dart';
import 'company_onboarding_screen.dart';
import 'login_screen.dart';

enum _GateState { signedOut, loadingProfile, needsCompany, ready, profileError }

class AuthProfileGate extends StatefulWidget {
  final SupabaseClient? client;
  final ProfileService? profileService;

  const AuthProfileGate({super.key, this.client, this.profileService})
    : assert(
        client == null || profileService == null,
        'Provide either client or profileService, not both.',
      );

  @override
  State<AuthProfileGate> createState() => _AuthProfileGateState();
}

class _AuthProfileGateState extends State<AuthProfileGate> {
  late final SupabaseClient client;
  late final ProfileService profileService;

  StreamSubscription<AuthState>? authSubscription;
  _GateState gateState = _GateState.signedOut;
  UserProfile? currentProfile;
  String? activeUserId;
  int profileRequestVersion = 0;
  bool isErrorSignOutInProgress = false;

  @override
  void initState() {
    super.initState();

    // An injected ProfileService must use the default Supabase client because
    // its internal client is intentionally not exposed for verification.
    client = widget.client ?? Supabase.instance.client;
    profileService = widget.profileService ?? ProfileService(client: client);

    final session = client.auth.currentSession;
    activeUserId = session?.user.id;
    gateState = session == null
        ? _GateState.signedOut
        : _GateState.loadingProfile;

    authSubscription = client.auth.onAuthStateChange.listen(
      handleAuthStateChange,
      onError: handleAuthStreamError,
    );

    if (session != null) {
      unawaited(loadCurrentProfile(expectedUserId: session.user.id));
    }
  }

  void handleAuthStateChange(AuthState authState) {
    if (!mounted) return;

    final session = authState.session;

    if (authState.event == AuthChangeEvent.signedOut || session == null) {
      showSignedOut();
      return;
    }

    final userId = session.user.id;
    final isSameUser = activeUserId == userId;

    if (isSameUser && gateState == _GateState.loadingProfile) {
      return;
    }

    if (isSameUser &&
        authState.event == AuthChangeEvent.tokenRefreshed &&
        gateState != _GateState.profileError) {
      return;
    }

    if (isSameUser &&
        (authState.event == AuthChangeEvent.initialSession ||
            authState.event == AuthChangeEvent.signedIn) &&
        (gateState == _GateState.needsCompany ||
            gateState == _GateState.ready)) {
      return;
    }

    unawaited(loadCurrentProfile(expectedUserId: userId));
  }

  void handleAuthStreamError(Object _, StackTrace _) {
    if (!mounted) return;

    if (client.auth.currentSession == null) {
      showSignedOut();
      return;
    }

    if (gateState == _GateState.loadingProfile) {
      profileRequestVersion++;
      setState(() {
        currentProfile = null;
        gateState = _GateState.profileError;
      });
    }
  }

  Future<void> loadCurrentProfile({String? expectedUserId}) async {
    final session = client.auth.currentSession;

    if (session == null) {
      showSignedOut();
      return;
    }

    final userId = session.user.id;

    if (expectedUserId != null && expectedUserId != userId) {
      return;
    }

    final requestVersion = ++profileRequestVersion;

    setState(() {
      activeUserId = userId;
      currentProfile = null;
      isErrorSignOutInProgress = false;
      gateState = _GateState.loadingProfile;
    });

    try {
      final profile = await profileService.fetchCurrentProfile();

      if (!isCurrentRequest(requestVersion, userId)) return;

      if (profile.userId != userId) {
        setState(() {
          gateState = _GateState.profileError;
        });
        return;
      }

      if (!profile.hasCompany) {
        setState(() {
          currentProfile = profile;
          gateState = _GateState.needsCompany;
        });
        return;
      }

      if (profile.company == null) {
        setState(() {
          currentProfile = profile;
          gateState = _GateState.profileError;
        });
        return;
      }

      setState(() {
        currentProfile = profile;
        gateState = _GateState.ready;
      });
    } catch (_) {
      if (!isCurrentRequest(requestVersion, userId)) return;

      setState(() {
        currentProfile = null;
        gateState = _GateState.profileError;
      });
    }
  }

  bool isCurrentRequest(int requestVersion, String userId) {
    if (!mounted || requestVersion != profileRequestVersion) {
      return false;
    }

    final session = client.auth.currentSession;
    return session != null &&
        session.user.id == userId &&
        activeUserId == userId;
  }

  void showSignedOut() {
    profileRequestVersion++;

    if (!mounted) return;

    setState(() {
      activeUserId = null;
      currentProfile = null;
      isErrorSignOutInProgress = false;
      gateState = _GateState.signedOut;
    });
  }

  void handleOnboardingCompleted() {
    unawaited(loadCurrentProfile());
  }

  Future<void> signOut() {
    return client.auth.signOut();
  }

  Future<void> signOutFromError() async {
    if (isErrorSignOutInProgress) return;

    setState(() {
      isErrorSignOutInProgress = true;
    });

    try {
      await signOut();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isErrorSignOutInProgress = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to sign out. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void retryProfileLoad() {
    if (isErrorSignOutInProgress) return;
    unawaited(loadCurrentProfile());
  }

  @override
  void dispose() {
    profileRequestVersion++;
    unawaited(authSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // LoginScreen currently pushes Home after sign-in, and HomeScreen currently
    // pushes Login after sign-out. Those navigation actions must be removed or
    // adapted before AuthProfileGate is wired into main.dart.
    switch (gateState) {
      case _GateState.signedOut:
        return const LoginScreen();
      case _GateState.loadingProfile:
        return buildLoadingState();
      case _GateState.needsCompany:
        return CompanyOnboardingScreen(
          profileService: profileService,
          onCompleted: handleOnboardingCompleted,
          onSignOut: signOut,
        );
      case _GateState.ready:
        return const HomeScreen();
      case _GateState.profileError:
        return buildProfileErrorState();
    }
  }

  Widget buildLoadingState() {
    return const Scaffold(
      backgroundColor: Color(0xFFF4F7F6),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_gas_station, size: 64, color: Color(0xFF168C4B)),
              SizedBox(height: 20),
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Loading your account...'),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildProfileErrorState() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('Account Setup'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_circle_outlined,
                  size: 70,
                  color: Color(0xFF168C4B),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Unable to Load Your Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your account information could not be verified. Please try again or sign out.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isErrorSignOutInProgress
                        ? null
                        : retryProfileLoad,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isErrorSignOutInProgress
                        ? null
                        : signOutFromError,
                    icon: isErrorSignOutInProgress
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout),
                    label: Text(
                      isErrorSignOutInProgress ? 'Signing Out...' : 'Sign Out',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
