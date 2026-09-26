-- 1. Ensure profiles table exists with balance, account number, safebox, and loan balances
CREATE TABLE IF NOT EXISTS public.profiles (
    user_id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    phone_number TEXT UNIQUE NOT NULL CHECK (phone_number ~ '^(07|08|09)[0-9]{9}$'),
    pin TEXT NOT NULL,
    account_no TEXT UNIQUE NOT NULL,
    profile_picture_url TEXT,
    kyc_tier TEXT DEFAULT 'Tier 3 Verified',
    balance NUMERIC(15, 2) DEFAULT 10000.00,
    safebox_balance NUMERIC(15, 2) DEFAULT 0.00,
    loan_balance NUMERIC(15, 2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Create transactions table for tracking history
CREATE TABLE IF NOT EXISTS public.transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT REFERENCES public.profiles(user_id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    subtitle TEXT NOT NULL,
    amount TEXT NOT NULL, -- formatted string e.g. "- ₦5,000.00"
    is_debit BOOLEAN NOT NULL,
    status TEXT DEFAULT 'Successful' NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Create biometric login logs table if not exists
CREATE TABLE IF NOT EXISTS public.biometric_login_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT REFERENCES public.profiles(user_id) ON DELETE CASCADE,
    auth_method TEXT NOT NULL, -- 'fingerprint'
    is_successful BOOLEAN NOT NULL,
    device_info TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 4. Disable Row Level Security (RLS) so client app can read/write without complex policies
ALTER TABLE public.profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.biometric_login_logs DISABLE ROW LEVEL SECURITY;

-- 6. Create admin_settings table for admin credentials
CREATE TABLE IF NOT EXISTS public.admin_settings (
    id INT PRIMARY KEY DEFAULT 1,
    username TEXT NOT NULL DEFAULT 'admin',
    password TEXT NOT NULL DEFAULT 'admin_password_2026',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT one_row CHECK (id = 1)
);

-- Insert default admin if not exists
INSERT INTO public.admin_settings (id, username, password)
VALUES (1, 'admin', 'admin_password_2026')
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.admin_settings DISABLE ROW LEVEL SECURITY;
