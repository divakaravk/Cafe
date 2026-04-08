-- ============================================================
-- CafePOS: Professional Schema (V2)
-- Based on the ERD from cafe_schema_overview.html
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. COMPANY_MASTER (Cafes/Companies)
CREATE TABLE "COMPANY_MASTER" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_code TEXT UNIQUE NOT NULL,
    company_name TEXT NOT NULL,
    address TEXT,
    city TEXT,
    state TEXT,
    country TEXT DEFAULT 'India',
    phone TEXT,
    email TEXT,
    has_gst BOOLEAN DEFAULT false,
    gstin TEXT,
    pan_number TEXT,
    has_table_management BOOLEAN DEFAULT true,
    has_item_variants BOOLEAN DEFAULT false,
    currency_code TEXT DEFAULT 'INR',
    timezone TEXT DEFAULT 'Asia/Kolkata',
    logo_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. COMPANY_HSN (GST Rates)
CREATE TABLE "COMPANY_HSN" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES "COMPANY_MASTER"(id) ON DELETE CASCADE,
    hsn_code TEXT NOT NULL,
    description TEXT,
    gst_rate DECIMAL(5,2) DEFAULT 0,
    cgst_rate DECIMAL(5,2) DEFAULT 0,
    sgst_rate DECIMAL(5,2) DEFAULT 0,
    igst_rate DECIMAL(5,2) DEFAULT 0,
    is_active BOOLEAN DEFAULT true
);

-- 3. COMPANY_PRINT_CONFIG
CREATE TABLE "COMPANY_PRINT_CONFIG" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID UNIQUE REFERENCES "COMPANY_MASTER"(id) ON DELETE CASCADE,
    printer_type TEXT DEFAULT 'THERMAL',
    paper_size TEXT DEFAULT '80mm',
    print_logo BOOLEAN DEFAULT true,
    print_gstin BOOLEAN DEFAULT true,
    print_hsn BOOLEAN DEFAULT true,
    print_qr_code BOOLEAN DEFAULT true,
    header_text TEXT,
    footer_text TEXT,
    copies_bill INTEGER DEFAULT 1,
    copies_kot INTEGER DEFAULT 1,
    auto_print_kot BOOLEAN DEFAULT true,
    auto_print_bill BOOLEAN DEFAULT false
);

-- 4. USER_MASTER (Staff/Profiles)
-- Note: id should match auth.users.id
CREATE TABLE "USER_MASTER" (
    id UUID PRIMARY KEY, -- References auth.users(id)
    company_id UUID REFERENCES "COMPANY_MASTER"(id) ON DELETE CASCADE,
    employee_code TEXT,
    full_name TEXT NOT NULL,
    username TEXT UNIQUE,
    role TEXT CHECK (role IN ('ADMIN', 'MANAGER', 'CASHIER', 'WAITER')),
    phone TEXT,
    email TEXT,
    is_active BOOLEAN DEFAULT true,
    last_login TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. USER_PREFERENCE
CREATE TABLE "USER_PREFERENCE" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES "USER_MASTER"(id) ON DELETE CASCADE,
    ui_theme_type TEXT DEFAULT 'MODERN',
    primary_color TEXT,
    accent_color TEXT,
    font_size TEXT DEFAULT 'MEDIUM',
    layout_mode TEXT DEFAULT 'GRID',
    dark_mode BOOLEAN DEFAULT true,
    chosen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. USER_PERMISSION
CREATE TABLE "USER_PERMISSION" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES "USER_MASTER"(id) ON DELETE CASCADE,
    can_view_dashboard BOOLEAN DEFAULT true,
    can_create_bill BOOLEAN DEFAULT true,
    can_edit_bill BOOLEAN DEFAULT true,
    can_cancel_bill BOOLEAN DEFAULT false,
    can_apply_discount BOOLEAN DEFAULT false,
    can_manage_items BOOLEAN DEFAULT false,
    can_manage_tables BOOLEAN DEFAULT false,
    can_view_reports BOOLEAN DEFAULT false,
    can_manage_users BOOLEAN DEFAULT false,
    can_manage_settings BOOLEAN DEFAULT false,
    can_void_items BOOLEAN DEFAULT false
);

-- 7. TABLE_MASTER
CREATE TABLE "TABLE_MASTER" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES "COMPANY_MASTER"(id) ON DELETE CASCADE,
    table_number TEXT NOT NULL,
    section TEXT,
    seating_capacity INTEGER DEFAULT 2,
    qr_code TEXT,
    is_active BOOLEAN DEFAULT true
);

-- 8. TABLE_SESSION (Dine-in management)
CREATE TABLE "TABLE_SESSION" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_id UUID REFERENCES "TABLE_MASTER"(id) ON DELETE CASCADE,
    opened_by UUID REFERENCES "USER_MASTER"(id),
    company_id UUID REFERENCES "COMPANY_MASTER"(id) ON DELETE CASCADE,
    opened_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    closed_at TIMESTAMP WITH TIME ZONE,
    status TEXT DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'CLOSED', 'CANCELLED')),
    covers INTEGER DEFAULT 1
);

-- 9. ITEM_GROUP
CREATE TABLE "ITEM_GROUP" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES "COMPANY_MASTER"(id) ON DELETE CASCADE,
    group_name TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    display_order INTEGER DEFAULT 0,
    show_subcategory BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true
);

-- 10. ITEM_MASTER
CREATE TABLE "ITEM_MASTER" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES "COMPANY_MASTER"(id) ON DELETE CASCADE,
    item_group_id UUID REFERENCES "ITEM_GROUP"(id) ON DELETE SET NULL,
    hsn_id UUID REFERENCES "COMPANY_HSN"(id) ON DELETE SET NULL,
    item_code TEXT,
    item_name TEXT NOT NULL,
    description TEXT,
    unit_of_measure TEXT DEFAULT 'NOS',
    base_rate DECIMAL(10,2) NOT NULL,
    has_variants BOOLEAN DEFAULT false,
    is_taxable BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    image_url TEXT,
    display_order INTEGER DEFAULT 0
);

-- 11. ITEM_VARIANT
CREATE TABLE "ITEM_VARIANT" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id UUID REFERENCES "ITEM_MASTER"(id) ON DELETE CASCADE,
    variant_name TEXT NOT NULL,
    rate_override DECIMAL(10,2),
    is_active BOOLEAN DEFAULT true
);

-- 12. BILL_MASTER
CREATE TABLE "BILL_MASTER" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES "COMPANY_MASTER"(id) ON DELETE CASCADE,
    table_session_id UUID REFERENCES "TABLE_SESSION"(id) ON DELETE SET NULL,
    billed_by UUID REFERENCES "USER_MASTER"(id),
    bill_number TEXT NOT NULL,
    bill_type TEXT DEFAULT 'DINING',
    bill_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    subtotal DECIMAL(10,2) NOT NULL,
    discount_amount DECIMAL(10,2) DEFAULT 0,
    discount_type TEXT DEFAULT 'PERCENT',
    taxable_amount DECIMAL(10,2) NOT NULL,
    cgst_amount DECIMAL(10,2) DEFAULT 0,
    sgst_amount DECIMAL(10,2) DEFAULT 0,
    igst_amount DECIMAL(10,2) DEFAULT 0,
    total_amount DECIMAL(10,2) NOT NULL,
    amount_paid DECIMAL(10,2) DEFAULT 0,
    change_amount DECIMAL(10,2) DEFAULT 0,
    payment_mode TEXT DEFAULT 'CASH',
    payment_ref TEXT,
    status TEXT DEFAULT 'PAID' CHECK (status IN ('PAID', 'PENDING', 'CANCELLED', 'VOID')),
    notes TEXT,
    is_printed BOOLEAN DEFAULT false,
    printed_at TIMESTAMP WITH TIME ZONE
);

-- 13. BILL_ITEM
CREATE TABLE "BILL_ITEM" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID REFERENCES "BILL_MASTER"(id) ON DELETE CASCADE,
    item_id UUID REFERENCES "ITEM_MASTER"(id),
    variant_id UUID REFERENCES "ITEM_VARIANT"(id),
    item_name_snapshot TEXT NOT NULL,
    rate_snapshot DECIMAL(10,2) NOT NULL,
    qty DECIMAL(10,2) NOT NULL,
    gross_amount DECIMAL(10,2) NOT NULL,
    discount_amount DECIMAL(10,2) DEFAULT 0,
    hsn_code_snapshot TEXT,
    gst_rate_snapshot DECIMAL(5,2) DEFAULT 0,
    cgst_amount DECIMAL(10,2) DEFAULT 0,
    sgst_amount DECIMAL(10,2) DEFAULT 0,
    igst_amount DECIMAL(10,2) DEFAULT 0,
    net_amount DECIMAL(10,2) NOT NULL,
    notes TEXT,
    kot_status TEXT DEFAULT 'PENDING',
    kot_printed_at TIMESTAMP WITH TIME ZONE
);

-- 14. KOT_MASTER (Kitchen Order Ticket)
CREATE TABLE "KOT_MASTER" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID REFERENCES "BILL_MASTER"(id) ON DELETE CASCADE,
    company_id UUID REFERENCES "COMPANY_MASTER"(id) ON DELETE CASCADE,
    table_session_id UUID REFERENCES "TABLE_SESSION"(id),
    kot_number TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES "USER_MASTER"(id),
    status TEXT DEFAULT 'PENDING',
    is_printed BOOLEAN DEFAULT false
);

-- 15. KOT_ITEM
CREATE TABLE "KOT_ITEM" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    kot_id UUID REFERENCES "KOT_MASTER"(id) ON DELETE CASCADE,
    bill_item_id UUID REFERENCES "BILL_ITEM"(id) ON DELETE CASCADE,
    qty DECIMAL(10,2) NOT NULL,
    notes TEXT,
    status TEXT DEFAULT 'PENDING'
);

-- ============================================================
-- RLS POLICIES (Basic Company Isolation)
-- ============================================================
ALTER TABLE "COMPANY_MASTER" ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON "COMPANY_MASTER" USING (id = (auth.jwt() ->> 'company_id')::UUID);

ALTER TABLE "ITEM_MASTER" ENABLE ROW LEVEL SECURITY;
CREATE POLICY item_isolation ON "ITEM_MASTER" USING (company_id = (auth.jwt() ->> 'company_id')::UUID);

-- (Extend to all other tables as needed)
