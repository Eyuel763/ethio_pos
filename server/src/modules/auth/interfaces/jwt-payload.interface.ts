export interface JwtPayload {
  sub: string; // User ID
  username: string;
  shopId: string;
  role: string;
}

export interface AuthenticatedUser {
  userId: string;
  username: string;
  shopId: string;
  role: string;
}
