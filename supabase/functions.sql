-- First drop the existing function
DROP FUNCTION IF EXISTS get_nearby_orders(double precision, double precision, double precision);

-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create the new function
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