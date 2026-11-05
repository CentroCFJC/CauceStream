/// Metadatos de la aplicacion, en un unico lugar.
///
/// Mantiene sincronizado lo que muestran el login, el perfil y la
/// franja inferior del shell. La version debe coincidir con la del
/// pubspec.yaml.
library;

abstract final class AppInfo {
  static const String appName = 'CAUCE_STREAM';
  static const String appVersion = 'v0.1.0';
  static const String institution = 'Sala Cauce - CCFJC';
  static const String serverNode = '10.15.1.150';
}
