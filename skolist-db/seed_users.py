"""
Seed script to create dummy users in Supabase auth.
Uses the Supabase Admin API to create users with email/password.
"""

import os

from dotenv import load_dotenv
load_dotenv()
from supabase import create_client, Client

# Configuration - update these or use environment variables
SUPABASE_URL = os.getenv("SUPABASE_URL", "http://127.0.0.1:54321")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

# Dummy users to seed
SEED_USERS = [
    {
        "email": "seed_user@skolist.com",
        "password": "password123",
        "user_metadata": {"name": "Seed User"},
    },
    {
        "email": "test@example.com",
        "password": "password123",
        "user_metadata": {"name": "Test User"},
    },
]


def get_supabase_admin_client() -> Client:
    """Create a Supabase client with service role key for admin operations."""
    if not SUPABASE_SERVICE_ROLE_KEY:
        raise ValueError(
            "SUPABASE_SERVICE_ROLE_KEY environment variable is required. "
            "You can find it by running: supabase status"
        )
    return create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def seed_users():
    """Seed dummy users into Supabase auth."""
    supabase = get_supabase_admin_client()

    print(f"Connecting to Supabase at: {SUPABASE_URL}")
    print(f"Seeding {len(SEED_USERS)} users...\n")

    for user_data in SEED_USERS:
        email = user_data["email"]
        try:
            # Use admin API to create user (bypasses email confirmation)
            response = supabase.auth.admin.create_user(
                {
                    "email": email,
                    "password": user_data["password"],
                    "email_confirm": True,  # Auto-confirm email
                    "user_metadata": user_data.get("user_metadata", {}),
                }
            )
            print(f"✓ Created user: {email} (ID: {response.user.id})")
        except Exception as e:
            error_msg = str(e)
            if "already been registered" in error_msg or "already exists" in error_msg:
                print(f"⚠ User already exists: {email}")
            else:
                print(f"✗ Failed to create user {email}: {error_msg}")

    print("\nSeeding complete!")


if __name__ == "__main__":
    seed_users()
