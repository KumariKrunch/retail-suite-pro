-- ================================================================
-- COMPLETE E-COMMERCE SCHEMA — FINAL (v1.0)
-- Stack  : PostgreSQL 17+, Rust/Axum, SQLx
-- Design : Single-merchant, DDD-aligned, event-sourced inventory
-- ================================================================
-- ================================================================
-- UTILITY: updated_at auto-maintenance (defined once, applied everywhere)
-- ================================================================
CREATE OR REPLACE FUNCTION trigger_set_updated_at ()
	RETURNS TRIGGER
	AS $$
BEGIN
	NEW.updated_at = NOW();
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

-- ================================================================
-- DOMAIN 1: IDENTITY — Users & Customers
-- ================================================================
CREATE TYPE principal_type AS ENUM (
	'user',
	'customer'
);

CREATE TABLE refresh_tokens (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	principal_type principal_type NOT NULL,
	principal_id UUID NOT NULL,
	token_hash VARCHAR(255) NOT NULL,
	-- device / client info (optional but useful)
	user_agent TEXT,
	ip_address INET,
	expires_at TIMESTAMPTZ NOT NULL,
	revoked_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_active_refresh_token UNIQUE (principal_type, principal_id, token_hash)
);

CREATE TYPE user_role AS ENUM (
	'admin',
	'staff',
	'cashier'
);

CREATE TABLE users (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	email VARCHAR(255) UNIQUE NOT NULL,
	password_hash VARCHAR(255) NOT NULL,
	first_name VARCHAR(100),
	last_name VARCHAR(100),
	ROLE user_role NOT NULL DEFAULT 'staff',
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	deleted_at TIMESTAMPTZ
);

CREATE TRIGGER set_updated_at_users
	BEFORE UPDATE ON users
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

CREATE TABLE customers (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	email VARCHAR(255) UNIQUE,
	first_name VARCHAR(100),
	last_name VARCHAR(100),
	phone VARCHAR(30),
	-- FIX [GDPR/PDPB]: DEFAULT FALSE — marketing consent requires explicit opt-in
	-- Defaulting TRUE violates GDPR Art.7 and India's DPDP Act 2023
	accepts_marketing BOOLEAN NOT NULL DEFAULT FALSE,
	notes TEXT,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	deleted_at TIMESTAMPTZ
);

CREATE TRIGGER set_updated_at_customers
	BEFORE UPDATE ON customers
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- Reusable address book; separate from immutable JSONB order snapshots
CREATE TABLE addresses (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	customer_id UUID REFERENCES customers (id),
	line1 VARCHAR(255) NOT NULL,
	line2 VARCHAR(255),
	city VARCHAR(100) NOT NULL,
	state VARCHAR(100) NOT NULL,
	country_code CHAR(2) NOT NULL,
	postal_code VARCHAR(20) NOT NULL,
	is_default BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_addresses
	BEFORE UPDATE ON addresses
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

CREATE TABLE customer_credentials (
	customer_id UUID PRIMARY KEY REFERENCES customers (id) ON DELETE CASCADE,
	password_hash VARCHAR(255) NOT NULL,
	last_login_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_customer_credentials
	BEFORE UPDATE ON customer_credentials
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- ================================================================
-- DOMAIN 2: CATALOG — Categories, Products & Variants
-- ================================================================
CREATE TYPE product_status AS ENUM (
	'draft',
	'active',
	'archived'
);

CREATE TYPE variant_status AS ENUM (
	'active',
	'archived'
);

-- Self-referential for hierarchy: Electronics > Laptops > Gaming
CREATE TABLE categories (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	name VARCHAR(255) NOT NULL,
	slug VARCHAR(255) UNIQUE NOT NULL,
	parent_id UUID REFERENCES categories (id),
	position INTEGER NOT NULL DEFAULT 0,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	deleted_at TIMESTAMPTZ
);

CREATE TRIGGER set_updated_at_categories
	BEFORE UPDATE ON categories
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

CREATE TABLE products (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	name VARCHAR(255) NOT NULL,
	slug VARCHAR(255) NOT NULL,
	description TEXT,
	category_id UUID REFERENCES categories (id),
	base_sku VARCHAR(100),
	status product_status NOT NULL DEFAULT 'draft',
	tags TEXT[],
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	deleted_at TIMESTAMPTZ
);

CREATE TRIGGER set_updated_at_products
	BEFORE UPDATE ON products
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

CREATE TABLE product_options (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	product_id UUID NOT NULL REFERENCES products (id) ON DELETE CASCADE,
	name VARCHAR(100) NOT NULL,
	position INTEGER NOT NULL DEFAULT 0,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE product_option_values (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	option_id UUID NOT NULL REFERENCES product_options (id) ON DELETE CASCADE,
	value VARCHAR(100) NOT NULL,
	position INTEGER NOT NULL DEFAULT 0,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE product_images (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	product_id UUID NOT NULL REFERENCES products (id),
	variant_id UUID NOT NULL REFERENCES product_variants (id),
	url TEXT NOT NULL,
	alt_text TEXT,
	position INTEGER NOT NULL DEFAULT 0,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- FIX: No price column — pricing lives entirely in Domain 3 (Price Lists)
-- FIX: manage_inventory flag added for digital/service products
-- FIX: deleted_at soft delete; hard delete breaks order_line_items FK
CREATE TABLE product_variants (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	product_id UUID NOT NULL REFERENCES products (id),
	sku VARCHAR(100) UNIQUE NOT NULL,
	barcode VARCHAR(100),
	weight_grams INTEGER,
	requires_shipping BOOLEAN NOT NULL DEFAULT TRUE,
	manage_inventory BOOLEAN NOT NULL DEFAULT TRUE,
	status variant_status NOT NULL DEFAULT 'active',
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	deleted_at TIMESTAMPTZ
);

CREATE TRIGGER set_updated_at_product_variants
	BEFORE UPDATE ON product_variants
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

CREATE TABLE variant_option_mapping (
	variant_id UUID NOT NULL REFERENCES product_variants (id),
	option_value_id UUID NOT NULL REFERENCES product_option_values (id),
	PRIMARY KEY (variant_id, option_value_id)
);

-- ================================================================
-- DOMAIN 3: PRICING — Price Lists
-- Solves: $100 USD != Rs.7,999 INR (psychological/regional pricing)
-- Solves: B2B tier pricing without duplicating catalog
-- ================================================================
-- FIX: is_active added; price lists can be deactivated without deletion
CREATE TABLE price_lists (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	name VARCHAR(100) NOT NULL,
	currency_code CHAR(3) NOT NULL,
	is_default BOOLEAN NOT NULL DEFAULT FALSE,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_price_lists
	BEFORE UPDATE ON price_lists
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- One row per (variant x price_list); no global price on variant
CREATE TABLE variant_prices (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	variant_id UUID NOT NULL REFERENCES product_variants (id),
	price_list_id UUID NOT NULL REFERENCES price_lists (id),
	price NUMERIC(15, 4) NOT NULL,
	compare_at_price INTEGER,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	UNIQUE (variant_id, price_list_id)
);

CREATE TRIGGER set_updated_at_variant_prices
	BEFORE UPDATE ON variant_prices
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- ================================================================
-- DOMAIN 4: INVENTORY — Event-Sourced with Resilient Outbox
-- ================================================================
CREATE TYPE location_type AS ENUM (
	'warehouse',
	'retail',
	'dropship'
);

CREATE TYPE inventory_event_type AS ENUM (
	'inbound_receipt',
	'reservation',
	'reservation_release',
	'sale_fulfillment',
	'return_restock',
	'damage_write_off',
	'manual_correction',
	'transfer_in',
	'transfer_out'
);

CREATE TYPE outbox_status AS ENUM (
	'pending',
	'processing',
	'published',
	'failed',
	'dead'
);

CREATE TABLE inventory_items (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	sku VARCHAR(100) UNIQUE NOT NULL,
	hs_code VARCHAR(20),
	country_of_origin CHAR(2),
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_inventory_items
	BEFORE UPDATE ON inventory_items
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- Bridge: 1:1 normally; 1:many for bundled products
CREATE TABLE product_variant_inventory_items (
	variant_id UUID NOT NULL REFERENCES product_variants (id),
	inventory_item_id UUID NOT NULL REFERENCES inventory_items (id),
	PRIMARY KEY (variant_id, inventory_item_id)
);

CREATE TABLE stock_locations (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	name VARCHAR(255) NOT NULL,
	address JSONB NOT NULL,
	location_type location_type NOT NULL DEFAULT 'warehouse',
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_stock_locations
	BEFORE UPDATE ON stock_locations
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- Immutable append-only ledger — NEVER UPDATE or DELETE rows here
-- This is the ground truth for all stock movements
CREATE TABLE inventory_events (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	inventory_item_id UUID NOT NULL REFERENCES inventory_items (id),
	location_id UUID NOT NULL REFERENCES stock_locations (id),
	event_type inventory_event_type NOT NULL,
	delta INTEGER NOT NULL,
	reference_type VARCHAR(50),
	reference_id UUID,
	performed_by UUID REFERENCES users (id),
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Materialized snapshot for fast storefront availability reads
-- Rebuilt atomically by background Tokio task from inventory_events
-- Rust service reads this table; never the raw event log for availability queries
CREATE TABLE inventory_snapshots (
	inventory_item_id UUID NOT NULL REFERENCES inventory_items (id),
	location_id UUID NOT NULL REFERENCES stock_locations (id),
	total_quantity INTEGER NOT NULL DEFAULT 0,
	reserved_quantity INTEGER NOT NULL DEFAULT 0,
	snapshot_at TIMESTAMPTZ NOT NULL,
	version INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (inventory_item_id, location_id),
	CONSTRAINT available_non_negative CHECK ((total_quantity - reserved_quantity) >= 0)
);

-- FIX: Dedicated sequence table for race-free per-aggregate outbox sequencing
-- ON CONFLICT DO UPDATE acts as an atomic increment under PostgreSQL row lock
-- Eliminates the MAX() + 1 subquery race condition in the Rust service
CREATE TABLE aggregate_sequences (
	aggregate_id UUID PRIMARY KEY,
	last_sequence BIGINT NOT NULL DEFAULT 0
);

-- Transactional outbox for cross-domain event publishing
-- Written atomically in the same transaction as inventory_events
-- FIX: UNIQUE(aggregate_id, aggregate_sequence) guarantees FIFO ordering
-- FIX: Resilience fields: locked_by, locked_until, retry_count, next_retry_at
CREATE TABLE inventory_outbox (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	aggregate_type VARCHAR(50) NOT NULL,
	aggregate_id UUID NOT NULL,
	aggregate_sequence BIGINT NOT NULL,
	event_type VARCHAR(100) NOT NULL,
	payload JSONB NOT NULL,
	status outbox_status NOT NULL DEFAULT 'pending',
	-- Distributed worker lease: prevents two Axum instances claiming same row
	locked_by UUID,
	locked_until TIMESTAMPTZ,
	-- Retry management with exponential backoff
	retry_count INTEGER NOT NULL DEFAULT 0,
	max_retries INTEGER NOT NULL DEFAULT 5,
	last_attempted_at TIMESTAMPTZ,
	next_retry_at TIMESTAMPTZ,
	last_error TEXT,
	published_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	-- FIX: Prevents duplicate sequence values from concurrent inserts
	CONSTRAINT uq_aggregate_sequence UNIQUE (aggregate_id, aggregate_sequence)
);

-- Dead letter archive: keeps hot outbox table clean from terminal failures
-- Includes manual resolution workflow for ops team
CREATE TABLE inventory_outbox_dead_letters (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	original_outbox_id UUID NOT NULL,
	aggregate_type VARCHAR(50) NOT NULL,
	aggregate_id UUID NOT NULL,
	event_type VARCHAR(100) NOT NULL,
	payload JSONB NOT NULL,
	retry_count INTEGER NOT NULL,
	final_error TEXT,
	moved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	resolved_at TIMESTAMPTZ,
	resolved_by UUID REFERENCES users (id),
	resolution_note TEXT
);

-- ================================================================
-- DOMAIN 5: PROMOTIONS — Engine + Discount Codes
-- Key principle: a discount code is a trigger, not the promotion itself
-- FIX: Supports automatic promotions (no code required)
-- FIX: BOGO modelled as separate line item at unit_price=0, not as adjustment
-- ================================================================
CREATE TYPE promotion_trigger AS ENUM (
	'automatic',
	'code',
	'customer_tag'
);

CREATE TYPE promotion_effect AS ENUM (
	'percentage_off_order',
	'fixed_amount_off_order',
	'percentage_off_line_item',
	'fixed_amount_off_line_item',
	'free_shipping',
	'buy_x_get_y_free'
);

CREATE TYPE allocation_method AS ENUM (
	'across',
	'each',
	'one'
);

CREATE TABLE promotions (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	title VARCHAR(255) NOT NULL,
	customer_description TEXT,
	trigger_type promotion_trigger NOT NULL,
	effect_type promotion_effect NOT NULL,
	allocation_method allocation_method NOT NULL DEFAULT 'across',
	value INTEGER NOT NULL,
	applies_to_product_ids UUID[],
	applies_to_category_ids UUID[],
	buy_quantity INTEGER,
	get_quantity INTEGER,
	minimum_order_amount NUMERIC(15, 4),
	minimum_quantity INTEGER,
	usage_limit INTEGER,
	usage_count INTEGER NOT NULL DEFAULT 0,
	per_customer_limit INTEGER NOT NULL DEFAULT 1,
	starts_at TIMESTAMPTZ,
	expires_at TIMESTAMPTZ,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_promotions
	BEFORE UPDATE ON promotions
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- Codes are one activation mechanism for a promotion, not the promotion itself
CREATE TABLE discount_codes (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	promotion_id UUID NOT NULL REFERENCES promotions (id),
	code VARCHAR(50) UNIQUE NOT NULL,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ================================================================
-- DOMAIN 6: TAX & SHIPPING
-- ================================================================
-- Rates stored as basis points: 1800 = 18.00%
CREATE TABLE tax_rates (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	name VARCHAR(100) NOT NULL,
	country_code CHAR(2) NOT NULL,
	state_code VARCHAR(10),
	rate_bps INTEGER NOT NULL,
	is_inclusive BOOLEAN NOT NULL DEFAULT FALSE,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_tax_rates
	BEFORE UPDATE ON tax_rates
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

CREATE TABLE shipping_zones (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	name VARCHAR(100) NOT NULL,
	country_codes TEXT[] NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- FIX: rate_type promoted from VARCHAR(20) to proper ENUM
CREATE TYPE shipping_rate_type AS ENUM (
	'flat',
	'weight_based',
	'price_based'
);

CREATE TABLE shipping_rates (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	zone_id UUID NOT NULL REFERENCES shipping_zones (id),
	name VARCHAR(100) NOT NULL,
	carrier VARCHAR(50),
	rate_type shipping_rate_type NOT NULL,
	min_weight_grams INTEGER,
	max_weight_grams INTEGER,
	min_order_amount NUMERIC(15, 4),
	price INTEGER NOT NULL,
	estimated_days_min INTEGER,
	estimated_days_max INTEGER,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_shipping_rates
	BEFORE UPDATE ON shipping_rates
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- ================================================================
-- DOMAIN 7: CHECKOUT SESSIONS
-- ================================================================
CREATE TYPE checkout_status AS ENUM (
	'active',
	'payment_pending',
	'converted',
	'abandoned',
	'expired'
);

CREATE TABLE checkout_sessions (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	customer_id UUID REFERENCES customers (id),
	price_list_id UUID REFERENCES price_lists (id),
	email VARCHAR(255),
	status checkout_status NOT NULL DEFAULT 'active',
	currency_code CHAR(3) NOT NULL,
	shipping_address JSONB,
	billing_address JSONB,
	shipping_rate_id UUID REFERENCES shipping_rates (id),
	-- FIX: Two promotion reference columns:
	--   discount_code_id: for code-triggered promotions
	--   promotion_id:     for automatic promotions that fire without a code
	discount_code_id UUID REFERENCES discount_codes (id),
	promotion_id UUID REFERENCES promotions (id),
	subtotal_amount NUMERIC(15, 4) NOT NULL DEFAULT 0,
	discount_amount NUMERIC(15, 4) NOT NULL DEFAULT 0,
	shipping_amount NUMERIC(15, 4) NOT NULL DEFAULT 0,
	tax_amount NUMERIC(15, 4) NOT NULL DEFAULT 0,
	total_amount NUMERIC(15, 4) NOT NULL DEFAULT 0,
	notes TEXT,
	expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '72 hours',
	converted_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_checkout_sessions
	BEFORE UPDATE ON checkout_sessions
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

CREATE TABLE checkout_session_items (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	session_id UUID NOT NULL REFERENCES checkout_sessions (id) ON DELETE CASCADE,
	variant_id UUID NOT NULL REFERENCES product_variants (id),
	quantity INTEGER NOT NULL CHECK (quantity > 0),
	unit_price_at_add INTEGER NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	UNIQUE (session_id, variant_id)
);

CREATE TRIGGER set_updated_at_checkout_session_items
	BEFORE UPDATE ON checkout_session_items
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- ================================================================
-- DOMAIN 8: ORDERS
-- Key invariant: order totals are denormalized aggregates of line items.
-- The line items are the source of truth; order-level totals are cached
-- for fast reads and must be recomputed whenever line items change.
-- ================================================================
CREATE TYPE order_status AS ENUM (
	'pending',
	'unfulfilled',
	'partially_fulfilled',
	'fulfilled',
	'canceled',
	'refunded'
);

CREATE TYPE financial_status AS ENUM (
	'pending',
	'authorized',
	'paid',
	'partially_refunded',
	'refunded',
	'voided'
);

CREATE TYPE sales_channel AS ENUM (
	'web',
	'pos',
	'api'
);

CREATE TABLE orders (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	order_number BIGSERIAL UNIQUE,
	customer_id UUID REFERENCES customers (id),
	email VARCHAR(255) NOT NULL,
	status order_status NOT NULL DEFAULT 'unfulfilled',
	financial_status financial_status NOT NULL DEFAULT 'pending',
	sales_channel sales_channel NOT NULL DEFAULT 'web',
	currency_code CHAR(3) NOT NULL,
	price_list_id UUID REFERENCES price_lists (id),
	-- Denormalized aggregates for fast reads (recomputed from line items on write)
	subtotal_amount NUMERIC(15, 4) NOT NULL,
	discount_amount NUMERIC(15, 4) NOT NULL DEFAULT 0,
	shipping_amount NUMERIC(15, 4) NOT NULL,
	tax_amount NUMERIC(15, 4) NOT NULL,
	total_amount NUMERIC(15, 4) NOT NULL,
	-- JSONB: immutable snapshots, queryable (city, country), won't corrupt history
	shipping_address JSONB NOT NULL,
	billing_address JSONB,
	checkout_session_id UUID REFERENCES checkout_sessions (id),
	notes TEXT,
	canceled_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_orders
	BEFORE UPDATE ON orders
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- Per-line financial breakdown is mandatory for correct partial refund math
CREATE TABLE order_line_items (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	order_id UUID NOT NULL REFERENCES orders (id),
	variant_id UUID REFERENCES product_variants (id),
	quantity INTEGER NOT NULL CHECK (quantity > 0),
	unit_price_paid NUMERIC(15, 4) NOT NULL,
	-- All amounts stored as positive integers
	gross_amount NUMERIC(15, 4) NOT NULL,
	discount_amount NUMERIC(15, 4) NOT NULL DEFAULT 0,
	tax_amount NUMERIC(15, 4) NOT NULL DEFAULT 0,
	net_amount NUMERIC(15, 4) NOT NULL,
	total_amount NUMERIC(15, 4) NOT NULL,
	-- Full snapshot: survives variant deletion, price changes, rebrands
	-- {"title":"Blue T-Shirt XL","sku":"TSH-BLU-XL","barcode":"...",
	--  "weight_grams":300,"options":{"Color":"Blue","Size":"XL"}}
	historical_snapshot JSONB NOT NULL,
	fulfilled_quantity INTEGER NOT NULL DEFAULT 0,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One row per promotion applied to a line; enables per-promo audit and reversal
-- amount is ALWAYS a negative integer (it is a deduction)
CREATE TABLE order_line_item_adjustments (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	line_item_id UUID NOT NULL REFERENCES order_line_items (id),
	promotion_id UUID REFERENCES promotions (id),
	description VARCHAR(255) NOT NULL,
	amount NUMERIC(15, 4) NOT NULL CHECK (amount <= 0),
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One row per tax component per line (CGST + SGST = two rows per Indian item)
CREATE TABLE order_line_item_tax_lines (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	line_item_id UUID NOT NULL REFERENCES order_line_items (id),
	tax_rate_id UUID REFERENCES tax_rates (id),
	title VARCHAR(100) NOT NULL,
	rate_bps INTEGER NOT NULL,
	amount NUMERIC(15, 4) NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Audit trail: which promotions fired on which orders
-- Used for usage_count enforcement and per-customer limit checks
CREATE TABLE promotion_usages (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	promotion_id UUID NOT NULL REFERENCES promotions (id),
	order_id UUID NOT NULL REFERENCES orders (id),
	customer_id UUID REFERENCES customers (id),
	discount_code_id UUID REFERENCES discount_codes (id),
	total_discount_applied INTEGER NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ================================================================
-- DOMAIN 9: INVENTORY RESERVATIONS & FULFILLMENT
-- ================================================================
-- FIX: reservation_status promoted from VARCHAR(20) to ENUM
CREATE TYPE reservation_status AS ENUM (
	'active',
	'released',
	'converted'
);

-- Locks stock at order placement; released on shipment or cancellation
CREATE TABLE inventory_reservations (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	line_item_id UUID NOT NULL REFERENCES order_line_items (id),
	inventory_item_id UUID NOT NULL REFERENCES inventory_items (id),
	location_id UUID NOT NULL REFERENCES stock_locations (id),
	quantity INTEGER NOT NULL CHECK (quantity > 0),
	status reservation_status NOT NULL DEFAULT 'active',
	released_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TYPE fulfillment_status AS ENUM (
	'pending',
	'in_progress',
	'shipped',
	'delivered',
	'failed',
	'canceled'
);

CREATE TABLE fulfillments (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	order_id UUID NOT NULL REFERENCES orders (id),
	location_id UUID NOT NULL REFERENCES stock_locations (id),
	status fulfillment_status NOT NULL DEFAULT 'pending',
	tracking_number VARCHAR(100),
	tracking_url TEXT,
	carrier VARCHAR(50),
	shipped_at TIMESTAMPTZ,
	delivered_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_fulfillments
	BEFORE UPDATE ON fulfillments
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

CREATE TABLE fulfillment_line_items (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	fulfillment_id UUID NOT NULL REFERENCES fulfillments (id),
	line_item_id UUID NOT NULL REFERENCES order_line_items (id),
	quantity INTEGER NOT NULL CHECK (quantity > 0),
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ================================================================
-- DOMAIN 10: RETURNS & REFUNDS
-- NOTE: Named 'return_requests' to avoid PostgreSQL reserved keyword
-- friction ('RETURN'/'RETURNS' heavily used in function definitions)
-- ================================================================
CREATE TYPE rma_status AS ENUM (
	'pending',
	'in_transit',
	'received',
	'refunded',
	'rejected'
);

CREATE TABLE return_requests (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	order_id UUID NOT NULL REFERENCES orders (id),
	status rma_status NOT NULL DEFAULT 'pending',
	reason TEXT,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_return_requests
	BEFORE UPDATE ON return_requests
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

CREATE TABLE return_line_items (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	return_id UUID NOT NULL REFERENCES return_requests (id),
	line_item_id UUID NOT NULL REFERENCES order_line_items (id),
	quantity INTEGER NOT NULL CHECK (quantity > 0),
	restock BOOLEAN NOT NULL DEFAULT TRUE,
	location_id UUID REFERENCES stock_locations (id),
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE refunds (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	order_id UUID NOT NULL REFERENCES orders (id),
	return_id UUID REFERENCES return_requests (id),
	total_amount NUMERIC(15, 4) NOT NULL,
	note TEXT,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Stores exact prorated math per refunded line for full auditability
-- Refund formula (application layer; Rust enforces this, not a DB constraint):
--   gross_refund    = unit_price_paid * quantity_returned
--   discount_refund = (quantity_returned / line.quantity) * line.discount_amount
--   tax_refund      = (quantity_returned / line.quantity) * line.tax_amount
--   net_refund      = gross_refund - discount_refund + tax_refund
-- BOGO exception: if line was a free promotional unit (unit_price_paid = 0),
-- gross_refund = 0 and net_refund = 0 by construction; no special flag needed
CREATE TABLE refund_line_items (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	refund_id UUID NOT NULL REFERENCES refunds (id),
	line_item_id UUID NOT NULL REFERENCES order_line_items (id),
	quantity_returned INTEGER NOT NULL CHECK (quantity_returned > 0),
	gross_refund INTEGER NOT NULL,
	discount_refund INTEGER NOT NULL,
	tax_refund INTEGER NOT NULL,
	net_refund INTEGER NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ================================================================
-- DOMAIN 11: PAYMENTS & BILLING
-- ================================================================
CREATE TYPE payment_provider AS ENUM (
	'stripe',
	'razorpay',
	'paypal',
	'upi',
	'pos_cash',
	'pos_card',
	'store_credit'
);

CREATE TYPE payment_status AS ENUM (
	'pending',
	'authorized',
	'captured',
	'failed',
	'refunded',
	'partially_refunded',
	'voided'
);

-- order_id is NULLABLE: supports pre-authorisation before order is confirmed
-- Avoids creating orphan order records when a card is declined
CREATE TABLE payments (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	order_id UUID REFERENCES orders (id),
	provider payment_provider NOT NULL,
	amount NUMERIC(15, 4) NOT NULL,
	currency_code CHAR(3) NOT NULL,
	status payment_status NOT NULL DEFAULT 'pending',
	idempotency_key VARCHAR(255) UNIQUE,
	gateway_transaction_id VARCHAR(255),
	gateway_response JSONB,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_updated_at_payments
	BEFORE UPDATE ON payments
	FOR EACH ROW
	EXECUTE FUNCTION trigger_set_updated_at ();

-- Partial refunds are first-class records, not just a status flag on payments
CREATE TABLE payment_refunds (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	payment_id UUID NOT NULL REFERENCES payments (id),
	refund_id UUID REFERENCES refunds (id),
	amount NUMERIC(15, 4) NOT NULL,
	reason TEXT,
	gateway_refund_id VARCHAR(255),
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Immutable webhook event log for every gateway callback
CREATE TABLE payment_events (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	payment_id UUID NOT NULL REFERENCES payments (id),
	event_type VARCHAR(100) NOT NULL,
	payload JSONB,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- FIX: version column added for optimistic locking (mirrors inventory pattern)
-- FIX: CHECK (balance >= 0) as DB-level overdraft guard
-- Concurrent redemptions handled with: UPDATE ... WHERE id = $1 AND version = $2
CREATE TABLE store_credits (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	customer_id UUID NOT NULL REFERENCES customers (id),
	balance INTEGER NOT NULL DEFAULT 0,
	version INTEGER NOT NULL DEFAULT 0,
	reason VARCHAR(255),
	expires_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	CONSTRAINT balance_non_negative CHECK (balance >= 0)
);

-- Immutable ledger: positive = credit added, negative = credit spent
CREATE TABLE store_credit_transactions (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	credit_id UUID NOT NULL REFERENCES store_credits (id),
	order_id UUID REFERENCES orders (id),
	delta INTEGER NOT NULL,
	note TEXT,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ================================================================
-- DOMAIN 12: POS — Shifts & Cash Drawer
-- ================================================================
-- FIX: drawer_transaction_type promoted from VARCHAR(20) to ENUM
CREATE TYPE drawer_transaction_type AS ENUM (
	'sale',
	'refund',
	'manual_in',
	'manual_out'
);

CREATE TABLE pos_shifts (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	location_id UUID NOT NULL REFERENCES stock_locations (id),
	user_id UUID NOT NULL REFERENCES users (id),
	opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	closed_at TIMESTAMPTZ,
	starting_cash INTEGER NOT NULL DEFAULT 0,
	expected_closing_cash INTEGER,
	declared_closing_cash INTEGER,
	-- FIX: GENERATED ALWAYS AS ensures this value never goes stale
	-- NULL when shift is still open (either source column is NULL)
	-- Populated automatically by PostgreSQL when shift is closed
	cash_discrepancy INTEGER GENERATED ALWAYS AS (declared_closing_cash - expected_closing_cash) STORED,
	notes TEXT,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE cash_drawer_transactions (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid (),
	shift_id UUID NOT NULL REFERENCES pos_shifts (id),
	order_id UUID REFERENCES orders (id),
	transaction_type drawer_transaction_type NOT NULL,
	amount NUMERIC(15, 4) NOT NULL,
	note TEXT,
	performed_by UUID NOT NULL REFERENCES users (id),
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ================================================================
-- INDEXES
-- ================================================================
-- Domain 1: Identity
CREATE INDEX idx_users_email ON users (email)
WHERE
	deleted_at IS NULL;

CREATE INDEX idx_customers_email ON customers (email)
WHERE
	deleted_at IS NULL;

CREATE INDEX idx_addresses_customer ON addresses (customer_id);

CREATE UNIQUE INDEX uq_customer_default_address ON addresses (customer_id)
WHERE
	is_default = TRUE;

-- Domain 2: Catalog
CREATE INDEX idx_products_category ON products (category_id)
WHERE
	deleted_at IS NULL;

CREATE INDEX idx_products_status ON products (status)
WHERE
	deleted_at IS NULL;

CREATE INDEX idx_variants_product ON product_variants (product_id)
WHERE
	deleted_at IS NULL;

CREATE INDEX idx_variants_sku ON product_variants (sku);

CREATE UNIQUE INDEX uq_products_slug ON products (slug)
WHERE
	deleted_at IS NULL;

CREATE INDEX idx_products_tags ON products USING gin (tags);

CREATE INDEX idx_product_images_product ON product_images (product_id);

-- Domain 3: Pricing
CREATE INDEX idx_variant_prices_variant ON variant_prices (variant_id);

CREATE INDEX idx_variant_prices_list ON variant_prices (price_list_id);

-- Domain 4: Inventory
CREATE INDEX idx_inv_events_item_loc ON inventory_events (inventory_item_id, location_id, created_at DESC);

CREATE INDEX idx_inv_snapshots_item ON inventory_snapshots (inventory_item_id, location_id);

-- Hot path: unpublished events ready for pickup
CREATE INDEX idx_outbox_claimable ON inventory_outbox (aggregate_id, aggregate_sequence)
WHERE
	status IN ('pending', 'failed');

-- Stale lease detection: worker crashed mid-processing
CREATE INDEX idx_outbox_stale_leases ON inventory_outbox (locked_until)
WHERE
	status = 'processing';

-- Domain 5: Promotions
CREATE INDEX idx_promotions_active ON promotions (starts_at, expires_at)
WHERE
	is_active = TRUE;

CREATE INDEX idx_discount_codes_code ON discount_codes (code)
WHERE
	is_active = TRUE;

CREATE INDEX idx_promotion_usages_promo ON promotion_usages (promotion_id);

CREATE INDEX idx_promotion_usages_customer ON promotion_usages (customer_id, promotion_id);

-- Domain 7: Checkout
CREATE INDEX idx_checkout_customer ON checkout_sessions (customer_id);

CREATE INDEX idx_checkout_expires ON checkout_sessions (expires_at)
WHERE
	status = 'active';

-- Domain 8: Orders
CREATE INDEX idx_orders_customer ON orders (customer_id);

CREATE INDEX idx_orders_created ON orders (created_at DESC);

CREATE INDEX idx_orders_status ON orders (status);

CREATE INDEX idx_orders_financial_status ON orders (financial_status);

CREATE INDEX idx_line_items_order ON order_line_items (order_id);

CREATE INDEX idx_line_adjustments_item ON order_line_item_adjustments (line_item_id);

CREATE INDEX idx_line_tax_lines_item ON order_line_item_tax_lines (line_item_id);

-- Domain 9: Reservations & Fulfillment
CREATE INDEX idx_reservations_line ON inventory_reservations (line_item_id);

CREATE INDEX idx_reservations_location ON inventory_reservations (location_id)
WHERE
	status = 'active';

CREATE INDEX idx_fulfillments_order ON fulfillments (order_id);

-- Domain 10: Returns & Refunds
CREATE INDEX idx_return_requests_order ON return_requests (order_id);

CREATE INDEX idx_refund_line_items_refund ON refund_line_items (refund_id);

-- Domain 11: Payments
CREATE INDEX idx_payments_order ON payments (order_id);

CREATE INDEX idx_payments_status ON payments (status);

CREATE INDEX idx_payment_events_payment ON payment_events (payment_id);

CREATE INDEX idx_store_credits_customer ON store_credits (customer_id);

CREATE INDEX idx_store_credit_txn_credit ON store_credit_transactions (credit_id);

-- Domain 12: POS
CREATE INDEX idx_pos_shifts_location ON pos_shifts (location_id);

CREATE INDEX idx_pos_shifts_user ON pos_shifts (user_id);

CREATE INDEX idx_cash_drawer_shift ON cash_drawer_transactions (shift_id);

