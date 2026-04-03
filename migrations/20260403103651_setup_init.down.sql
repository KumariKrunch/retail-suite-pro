-- ================================================================
-- COMPLETE E-COMMERCE SCHEMA — DOWN MIGRATION (v1.0)
-- Stack  : PostgreSQL 17+, Rust/Axum, SQLx
-- WARNING: This will destroy all data. Use for local dev/CI only.
-- ================================================================
-- ================================================================
-- 1. DROP TABLES (Reverse Dependency Order)
-- ================================================================
-- Domain 12: POS
DROP TABLE IF EXISTS cash_drawer_transactions CASCADE;

DROP TABLE IF EXISTS pos_shifts CASCADE;

-- Domain 11: Payments
DROP TABLE IF EXISTS store_credit_transactions CASCADE;

DROP TABLE IF EXISTS store_credits CASCADE;

DROP TABLE IF EXISTS payment_events CASCADE;

DROP TABLE IF EXISTS payment_refunds CASCADE;

DROP TABLE IF EXISTS payments CASCADE;

-- Domain 10: Returns & Refunds
DROP TABLE IF EXISTS refund_line_items CASCADE;

DROP TABLE IF EXISTS refunds CASCADE;

DROP TABLE IF EXISTS return_line_items CASCADE;

DROP TABLE IF EXISTS return_requests CASCADE;

-- Domain 9: Inventory Reservations & Fulfillment
DROP TABLE IF EXISTS fulfillment_line_items CASCADE;

DROP TABLE IF EXISTS fulfillments CASCADE;

DROP TABLE IF EXISTS inventory_reservations CASCADE;

-- Domain 8: Orders
DROP TABLE IF EXISTS promotion_usages CASCADE;

DROP TABLE IF EXISTS order_line_item_tax_lines CASCADE;

DROP TABLE IF EXISTS order_line_item_adjustments CASCADE;

DROP TABLE IF EXISTS order_line_items CASCADE;

DROP TABLE IF EXISTS orders CASCADE;

-- Domain 7: Checkout
DROP TABLE IF EXISTS checkout_session_items CASCADE;

DROP TABLE IF EXISTS checkout_sessions CASCADE;

-- Domain 6: Tax & Shipping
DROP TABLE IF EXISTS shipping_rates CASCADE;

DROP TABLE IF EXISTS shipping_zones CASCADE;

DROP TABLE IF EXISTS tax_rates CASCADE;

-- Domain 5: Promotions
DROP TABLE IF EXISTS discount_codes CASCADE;

DROP TABLE IF EXISTS promotions CASCADE;

-- Domain 4: Inventory
DROP TABLE IF EXISTS inventory_outbox_dead_letters CASCADE;

DROP TABLE IF EXISTS inventory_outbox CASCADE;

DROP TABLE IF EXISTS aggregate_sequences CASCADE;

DROP TABLE IF EXISTS inventory_snapshots CASCADE;

DROP TABLE IF EXISTS inventory_events CASCADE;

DROP TABLE IF EXISTS stock_locations CASCADE;

DROP TABLE IF EXISTS product_variant_inventory_items CASCADE;

DROP TABLE IF EXISTS inventory_items CASCADE;

-- Domain 3: Pricing
DROP TABLE IF EXISTS variant_prices CASCADE;

DROP TABLE IF EXISTS price_lists CASCADE;

-- Domain 2: Catalog
DROP TABLE IF EXISTS variant_option_mapping CASCADE;

DROP TABLE IF EXISTS product_images CASCADE;

DROP TABLE IF EXISTS product_variants CASCADE;

DROP TABLE IF EXISTS product_option_values CASCADE;

DROP TABLE IF EXISTS product_options CASCADE;

DROP TABLE IF EXISTS products CASCADE;

DROP TABLE IF EXISTS categories CASCADE;

-- Domain 1: Identity
DROP TABLE IF EXISTS addresses CASCADE;

DROP TABLE IF EXISTS customers CASCADE;

DROP TABLE IF EXISTS users CASCADE;

-- ================================================================
-- 2. DROP ENUMS (Custom Types)
-- ================================================================
DROP TYPE IF EXISTS drawer_transaction_type CASCADE;

DROP TYPE IF EXISTS payment_status CASCADE;

DROP TYPE IF EXISTS payment_provider CASCADE;

DROP TYPE IF EXISTS rma_status CASCADE;

DROP TYPE IF EXISTS fulfillment_status CASCADE;

DROP TYPE IF EXISTS reservation_status CASCADE;

DROP TYPE IF EXISTS sales_channel CASCADE;

DROP TYPE IF EXISTS financial_status CASCADE;

DROP TYPE IF EXISTS order_status CASCADE;

DROP TYPE IF EXISTS checkout_status CASCADE;

DROP TYPE IF EXISTS shipping_rate_type CASCADE;

DROP TYPE IF EXISTS allocation_method CASCADE;

DROP TYPE IF EXISTS promotion_effect CASCADE;

DROP TYPE IF EXISTS promotion_trigger CASCADE;

DROP TYPE IF EXISTS outbox_status CASCADE;

DROP TYPE IF EXISTS inventory_event_type CASCADE;

DROP TYPE IF EXISTS location_type CASCADE;

DROP TYPE IF EXISTS variant_status CASCADE;

DROP TYPE IF EXISTS product_status CASCADE;

DROP TYPE IF EXISTS user_role CASCADE;

-- ================================================================
-- 3. DROP UTILITY FUNCTIONS
-- ================================================================
DROP FUNCTION IF EXISTS trigger_set_updated_at () CASCADE;

