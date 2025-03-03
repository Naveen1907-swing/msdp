-- Create enum for user roles
CREATE TYPE user_role AS ENUM ('customer', 'driver', 'warehouse_admin');

-- Create users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  role user_role NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
  full_name TEXT,
  phone_number TEXT
);

-- Create warehouse_details table
CREATE TABLE warehouse_details (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  warehouse_name TEXT NOT NULL,
  address TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
  latitude double precision NOT NULL DEFAULT 0.0,
  longitude double precision NOT NULL DEFAULT 0.0
);

-- Create driver_details table
CREATE TABLE driver_details (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  vehicle_number TEXT NOT NULL,
  license_number TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- Insert customer users
INSERT INTO users (id, email, role, full_name, phone_number) VALUES
('d7bed83f-3c51-4195-8db2-4e4c1a26c5f1', 'customer1@example.com', 'customer', 'John Doe', '+1234567890'),
('e8bed83f-3c51-4195-8db2-4e4c1a26c5f2', 'customer2@example.com', 'customer', 'Jane Smith', '+1234567891');

-- Insert driver users
INSERT INTO users (id, email, role, full_name, phone_number) VALUES
('f9bed83f-3c51-4195-8db2-4e4c1a26c5f3', 'driver1@example.com', 'driver', 'Mike Johnson', '+1234567892'),
('a1bed83f-3c51-4195-8db2-4e4c1a26c5f4', 'driver2@example.com', 'driver', 'Sarah Wilson', '+1234567893');

-- Insert warehouse admin users
INSERT INTO users (id, email, role, full_name, phone_number) VALUES
('b2bed83f-3c51-4195-8db2-4e4c1a26c5f5', 'warehouse1@example.com', 'warehouse_admin', 'Robert Brown', '+1234567894'),
('c3bed83f-3c51-4195-8db2-4e4c1a26c5f6', 'warehouse2@example.com', 'warehouse_admin', 'Lisa Davis', '+1234567895');

-- Insert driver details
INSERT INTO driver_details (user_id, vehicle_number, license_number) VALUES
('f9bed83f-3c51-4195-8db2-4e4c1a26c5f3', 'VH-1234', 'DL-98765'),
('a1bed83f-3c51-4195-8db2-4e4c1a26c5f4', 'VH-5678', 'DL-12345');

-- Insert warehouse details
INSERT INTO warehouse_details (user_id, warehouse_name, address) VALUES
('b2bed83f-3c51-4195-8db2-4e4c1a26c5f5', 'Central Warehouse', '123 Main St, City, Country'),
('c3bed83f-3c51-4195-8db2-4e4c1a26c5f6', 'East Coast Warehouse', '456 East St, City, Country');

-- Add scheduled_delivery column to orders table
ALTER TABLE orders ADD COLUMN scheduled_delivery TIMESTAMP WITH TIME ZONE;

-- Update existing warehouse coordinates (replace with actual coordinates)
UPDATE warehouse_details
SET latitude = 37.7749, longitude = -122.4194
WHERE latitude = 0 AND longitude = 0;

-- Initialize tracking data for existing orders
UPDATE orders
SET 
    tracking_updates = jsonb_build_array(
        jsonb_build_object(
            'timestamp', created_at,
            'latitude', COALESCE(pickup_latitude, 0),
            'longitude', COALESCE(pickup_longitude, 0),
            'status', status
        )
    )
WHERE tracking_updates IS NULL OR tracking_updates = '[]'::jsonb;

-- Add tracking-related columns to orders table if they don't exist
DO $$ 
BEGIN
    -- Add current_location columns for real-time tracking
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'current_latitude'
    ) THEN
        ALTER TABLE orders ADD COLUMN current_latitude double precision;
        ALTER TABLE orders ADD COLUMN current_longitude double precision;
    END IF;

    -- Add estimated delivery time
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'estimated_delivery_time'
    ) THEN
        ALTER TABLE orders ADD COLUMN estimated_delivery_time TIMESTAMP WITH TIME ZONE;
    END IF;

    -- Add tracking updates JSON array
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'tracking_updates'
    ) THEN
        ALTER TABLE orders ADD COLUMN tracking_updates JSONB DEFAULT '[]'::jsonb;
    END IF;
END $$;

-- Create function to update tracking information
CREATE OR REPLACE FUNCTION update_order_tracking(
    order_id UUID,
    curr_lat double precision,
    curr_lng double precision,
    status_update TEXT DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    tracking_entry JSONB;
BEGIN
    -- Create tracking entry
    tracking_entry = jsonb_build_object(
        'timestamp', CURRENT_TIMESTAMP,
        'latitude', curr_lat,
        'longitude', curr_lng,
        'status', COALESCE(status_update, (SELECT status FROM orders WHERE id = order_id))
    );

    -- Update order with current location and add tracking entry
    UPDATE orders
    SET 
        current_latitude = curr_lat,
        current_longitude = curr_lng,
        tracking_updates = tracking_updates || tracking_entry
    WHERE id = order_id;
END;
$$ LANGUAGE plpgsql;

-- Create function to get order tracking history
CREATE OR REPLACE FUNCTION get_order_tracking(
    order_id UUID
)
RETURNS TABLE (
    current_lat double precision,
    current_lng double precision,
    estimated_delivery TIMESTAMP WITH TIME ZONE,
    status TEXT,
    tracking_history JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.current_latitude,
        o.current_longitude,
        o.estimated_delivery_time,
        o.status,
        o.tracking_updates
    FROM orders o
    WHERE o.id = order_id;
END;
$$ LANGUAGE plpgsql;

-- Create function to calculate estimated delivery time
CREATE OR REPLACE FUNCTION update_estimated_delivery_time(
    order_id UUID,
    speed_kmh double precision DEFAULT 30
)
RETURNS void AS $$
DECLARE
    distance_km double precision;
    estimated_hours double precision;
BEGIN
    -- Calculate distance between current location and delivery location
    SELECT 
        ST_Distance(
            ST_SetSRID(ST_MakePoint(current_longitude, current_latitude), 4326)::geography,
            ST_SetSRID(ST_MakePoint(delivery_longitude, delivery_latitude), 4326)::geography
        ) / 1000 -- Convert meters to kilometers
    INTO distance_km
    FROM orders
    WHERE id = order_id;

    -- Calculate estimated time based on distance and average speed
    estimated_hours = distance_km / speed_kmh;

    -- Update estimated delivery time
    UPDATE orders
    SET estimated_delivery_time = CURRENT_TIMESTAMP + (estimated_hours || ' hours')::interval
    WHERE id = order_id;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update estimated delivery time when location changes
CREATE OR REPLACE FUNCTION trigger_update_delivery_estimate()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.current_latitude IS NOT NULL AND NEW.current_longitude IS NOT NULL THEN
        PERFORM update_estimated_delivery_time(NEW.id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_delivery_estimate ON orders;
CREATE TRIGGER update_delivery_estimate
    AFTER UPDATE OF current_latitude, current_longitude ON orders
    FOR EACH ROW
    EXECUTE FUNCTION trigger_update_delivery_estimate();

-- Example of how to use the tracking functions:
COMMENT ON FUNCTION update_order_tracking IS '
Example usage:
SELECT update_order_tracking(
    ''order-uuid-here'',
    37.7749,
    -122.4194,
    ''in_progress''
);
';

COMMENT ON FUNCTION get_order_tracking IS '
Example usage:
SELECT * FROM get_order_tracking(''order-uuid-here'');
';

-- First, check if the status column exists and its current type
DO $$ 
BEGIN
    -- Add status column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'status'
    ) THEN
        ALTER TABLE orders ADD COLUMN status TEXT DEFAULT 'pending';
    END IF;
END $$;

-- Update existing statuses to ensure consistency
UPDATE orders 
SET status = CASE 
    WHEN status IS NULL THEN 'pending'
    WHEN status = 'at_warehouse' THEN 'at_warehouse'
    WHEN status = 'in_progress' THEN 'in_progress'
    WHEN status = 'completed' THEN 'completed'
    WHEN status = 'cancelled' THEN 'cancelled'
    ELSE 'pending'
END;

-- Create trigger function for status updates
CREATE OR REPLACE FUNCTION update_order_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Update status when order reaches warehouse
    IF NEW.warehouse_id IS NOT NULL AND OLD.warehouse_id IS NULL THEN
        NEW.status = 'at_warehouse';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists and create new one
DROP TRIGGER IF EXISTS order_status_update ON orders;
CREATE TRIGGER order_status_update
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_order_status();

-- Update the get_nearby_orders function to use text status
CREATE OR REPLACE FUNCTION get_nearby_orders(
    driver_lat double precision,
    driver_lng double precision,
    radius_meters double precision
)
RETURNS TABLE (
    id UUID,
    delivery_address TEXT,
    pickup_address TEXT,
    delivery_latitude double precision,
    delivery_longitude double precision,
    pickup_latitude double precision,
    pickup_longitude double precision,
    distance_meters double precision
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.id,
        o.delivery_address,
        o.pickup_address,
        o.delivery_latitude,
        o.delivery_longitude,
        o.pickup_latitude,
        o.pickup_longitude,
        ST_Distance(
            ST_SetSRID(ST_MakePoint(driver_lng, driver_lat), 4326)::geography,
            ST_SetSRID(ST_MakePoint(o.delivery_longitude, o.delivery_latitude), 4326)::geography
        ) as distance_meters
    FROM orders o
    WHERE 
        o.status = 'pending'
        AND o.driver_id IS NULL
        AND ST_DWithin(
            ST_SetSRID(ST_MakePoint(driver_lng, driver_lat), 4326)::geography,
            ST_SetSRID(ST_MakePoint(o.delivery_longitude, o.delivery_latitude), 4326)::geography,
            radius_meters
        )
    ORDER BY distance_meters ASC;
END;
$$ LANGUAGE plpgsql;
