class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? token;
  final String? shopId;
  final String? shopName;
  final String? username;
  final String? fullName;
  final String? errorMessage;
  final bool isOfflineDemo;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.token,
    this.shopId,
    this.shopName,
    this.username,
    this.fullName,
    this.errorMessage,
    this.isOfflineDemo = false,
  });

  const AuthState.initial()
      : isAuthenticated = false,
        isLoading = false,
        token = null,
        shopId = null,
        shopName = null,
        username = null,
        fullName = null,
        errorMessage = null,
        isOfflineDemo = false;

  const AuthState.authenticated({
    required this.token,
    required this.shopId,
    required this.shopName,
    required this.username,
    this.fullName,
    this.isOfflineDemo = false,
  })  : isAuthenticated = true,
        isLoading = false,
        errorMessage = null;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? token,
    String? shopId,
    String? shopName,
    String? username,
    String? fullName,
    String? errorMessage,
    bool? isOfflineDemo,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      token: token ?? this.token,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      errorMessage: errorMessage,
      isOfflineDemo: isOfflineDemo ?? this.isOfflineDemo,
    );
  }
}
