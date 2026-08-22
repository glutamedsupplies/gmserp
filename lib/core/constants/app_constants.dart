class AppConstants {
  AppConstants._();

  static const String appName = 'GMSERP';

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;

  // Auth form layout
  static const double authFormMaxWidth = 480;
  static const double authCardPadding = 32;
  static const double mobileHorizontalPadding = 20;

  // Animation
  static const Duration shortAnimation = Duration(milliseconds: 250);
  static const Duration mediumAnimation = Duration(milliseconds: 400);

  // Mock auth delay to simulate network latency
  static const Duration mockNetworkDelay = Duration(milliseconds: 1200);
}
