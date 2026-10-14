class AppUser {
  final String displayName;
  final String email;
  final String? photoUrl;

  const AppUser({
    required this.displayName,
    required this.email,
    this.photoUrl,
  });
}
