#!/usr/bin/env python3
"""
MDM Location Polling Script

Polls SimpleMDM API for device locations and stores them in PostgreSQL.
Supports multiple devices via comma-separated device IDs.
Runs as a sidecar or CronJob in the cluster.
"""

import os
import sys
import time
import logging
import requests
import psycopg
from datetime import datetime, timezone

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration from environment
SIMPLEMDM_API_KEY = os.environ.get('SIMPLEMDM_API_KEY', '2IkV3x1TEpS9r6AGtmeyvLlBMvwHzCeJgQY4O8VyTtoss2KR6qVpEZcQqPlmLrLV')
# Support multiple device IDs (comma-separated)
# Default: iPhone (2154382) and MacBook Air (2162127)
SIMPLEMDM_DEVICE_IDS = os.environ.get('SIMPLEMDM_DEVICE_IDS', '2154382,2162127').split(',')
POLL_INTERVAL_SECONDS = int(os.environ.get('POLL_INTERVAL_SECONDS', '30'))

# Database configuration
POSTGRES_HOST = os.environ.get('POSTGRES_HOST', 'postgres-service.hocuspocus.svc.cluster.local')
POSTGRES_PORT = os.environ.get('POSTGRES_PORT', '5432')
POSTGRES_DB = os.environ.get('POSTGRES_DB', 'mitmproxy')
POSTGRES_USER = os.environ.get('POSTGRES_USER', 'mitmproxy')
POSTGRES_PASSWORD = os.environ.get('POSTGRES_PASSWORD', '')


def get_device_location(device_id: str):
    """Fetch device location from SimpleMDM API."""
    url = f"https://a.simplemdm.com/api/v1/devices/{device_id}"

    try:
        response = requests.get(
            url,
            auth=(SIMPLEMDM_API_KEY, ''),
            timeout=10
        )
        response.raise_for_status()

        data = response.json()
        attrs = data.get('data', {}).get('attributes', {})

        device_name = attrs.get('name', device_id)
        lat = attrs.get('location_latitude')
        lng = attrs.get('location_longitude')
        accuracy = attrs.get('location_accuracy')
        updated_at = attrs.get('location_updated_at')

        if lat and lng:
            logger.info(f"📍 [{device_name}] Got location: lat={lat}, lng={lng}, accuracy={accuracy}m")
            return {
                'device_id': device_id,
                'device_name': device_name,
                'latitude': float(lat),
                'longitude': float(lng),
                'accuracy': accuracy,
                'location_updated_at': updated_at
            }
        else:
            logger.warning(f"⚠️ [{device_name}] Location not available from MDM")
            return None

    except requests.RequestException as e:
        logger.error(f"❌ [{device_id}] Failed to fetch location from SimpleMDM: {e}")
        return None


def request_location_update(device_id: str):
    """Request a fresh location update from the device."""
    url = f"https://a.simplemdm.com/api/v1/devices/{device_id}/lost_mode/update_location"

    try:
        response = requests.post(
            url,
            auth=(SIMPLEMDM_API_KEY, ''),
            timeout=10
        )
        if response.status_code == 202:
            logger.info(f"📍 [{device_id}] Requested location update from device")
            return True
        else:
            logger.warning(f"⚠️ [{device_id}] Location update request returned {response.status_code}")
            return False
    except requests.RequestException as e:
        logger.error(f"❌ [{device_id}] Failed to request location update: {e}")
        return False


def get_connection_string():
    """Build PostgreSQL connection string."""
    return f"postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"


def store_location(location):
    """Store location in PostgreSQL database."""
    device_id = location['device_id']
    device_name = location.get('device_name', device_id)

    try:
        with psycopg.connect(get_connection_string()) as conn:
            with conn.cursor() as cursor:
                # Upsert location data
                cursor.execute("""
                    INSERT INTO device_locations (device_id, latitude, longitude, accuracy, location_updated_at, fetched_at)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (device_id)
                    DO UPDATE SET
                        latitude = EXCLUDED.latitude,
                        longitude = EXCLUDED.longitude,
                        accuracy = EXCLUDED.accuracy,
                        location_updated_at = EXCLUDED.location_updated_at,
                        fetched_at = EXCLUDED.fetched_at
                """, (
                    device_id,
                    location['latitude'],
                    location['longitude'],
                    location['accuracy'],
                    location['location_updated_at'],
                    datetime.now(timezone.utc)
                ))
                conn.commit()

        logger.info(f"✅ [{device_name}] Stored location in database")
        return True

    except psycopg.Error as e:
        logger.error(f"❌ [{device_name}] Database error: {e}")
        return False


def ensure_table_exists():
    """Create device_locations table if it doesn't exist."""
    try:
        with psycopg.connect(get_connection_string()) as conn:
            with conn.cursor() as cursor:
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS device_locations (
                        id SERIAL PRIMARY KEY,
                        device_id VARCHAR(255) NOT NULL UNIQUE,
                        latitude DECIMAL(10, 8) NOT NULL,
                        longitude DECIMAL(11, 8) NOT NULL,
                        accuracy INTEGER,
                        location_updated_at TIMESTAMP,
                        fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    );
                    CREATE INDEX IF NOT EXISTS idx_device_locations_device_id ON device_locations(device_id);
                """)
                conn.commit()

        logger.info("✅ Database table ready")
        return True

    except psycopg.Error as e:
        logger.error(f"❌ Failed to create table: {e}")
        return False


def main():
    """Main polling loop."""
    logger.info(f"🚀 Starting MDM location polling")
    logger.info(f"   Device IDs: {SIMPLEMDM_DEVICE_IDS}")
    logger.info(f"   Poll interval: {POLL_INTERVAL_SECONDS}s")
    logger.info(f"   Database: {POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}")

    # Ensure table exists
    if not ensure_table_exists():
        logger.error("Failed to initialize database, exiting")
        sys.exit(1)

    while True:
        for device_id in SIMPLEMDM_DEVICE_IDS:
            device_id = device_id.strip()
            if not device_id:
                continue

            try:
                # Get current location for this device
                location = get_device_location(device_id)

                if location:
                    store_location(location)
                else:
                    # Request a location update if none available
                    request_location_update(device_id)

            except Exception as e:
                logger.error(f"❌ [{device_id}] Error in polling loop: {e}")

        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == '__main__':
    main()
