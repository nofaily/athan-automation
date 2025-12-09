#!/usr/bin/env python3
"""
Prayer Times Calculator
Calculates prayer times for a date range and outputs to CSV
"""

import csv
from datetime import datetime, timedelta
from praytimes import PrayTimes
from hijridate import Hijri, Gregorian


def get_float_input(prompt, min_val=None, max_val=None):
    """Get validated float input from user"""
    while True:
        try:
            value = float(input(prompt))
            if min_val is not None and value < min_val:
                print(f"Value must be >= {min_val}")
                continue
            if max_val is not None and value > max_val:
                print(f"Value must be <= {max_val}")
                continue
            return value
        except ValueError:
            print("Invalid input. Please enter a number.")


def get_date_input(prompt):
    """Get validated date input from user"""
    while True:
        date_str = input(prompt)
        try:
            date_obj = datetime.strptime(date_str, "%Y-%m-%d")
            return date_obj
        except ValueError:
            print("Invalid date format. Please use YYYY-MM-DD (e.g., 2025-01-15)")


def get_choice_input(prompt, options):
    """Get validated choice from options"""
    print(prompt)
    for i, option in enumerate(options, 1):
        print(f"{i}. {option}")
    
    while True:
        try:
            choice = int(input("Enter choice number: "))
            if 1 <= choice <= len(options):
                return choice - 1
            print(f"Please enter a number between 1 and {len(options)}")
        except ValueError:
            print("Invalid input. Please enter a number.")


def get_hijri_month_name(date_obj):
    """Convert Gregorian date to Hijri and return Arabic month name"""
    hijri_months = [
        "Muharram", "Safar", "Rabi' al-Awwal", "Rabi' al-Thani",
        "Jumada al-Awwal", "Jumada al-Thani", "Rajab", "Sha'ban",
        "Ramadan", "Shawwal", "Dhu al-Qi'dah", "Dhu al-Hijjah"
    ]
    
    gregorian = Gregorian(date_obj.year, date_obj.month, date_obj.day)
    hijri = gregorian.to_hijri()
    return hijri_months[hijri.month - 1]


def get_timezone_offset(date_obj):
    """Get timezone offset for a specific date (handles DST automatically)"""
    # Get the local timezone offset including DST
    timestamp = date_obj.timestamp()
    local_time = datetime.fromtimestamp(timestamp)
    utc_time = datetime.utcfromtimestamp(timestamp)
    offset = (local_time - utc_time).total_seconds() / 3600
    return offset


def main():
    print("=== Prayer Times Calculator ===\n")
    
    # Get location
    print("Enter your location coordinates:")
    latitude = get_float_input("Latitude (-90 to 90): ", -90, 90)
    longitude = get_float_input("Longitude (-180 to 180): ", -180, 180)
    
    # Get calculation methods
    print("\n--- Calculation Methods ---")
    
    fajr_isha_methods = [
        "Ithna Ashari",
        "University of Islamic Sciences, Karachi",
        "Islamic Society of North America (ISNA)",
        "Muslim World League (MWL)",
        "Umm al-Qura, Makkah",
        "Egyptian General Authority of Survey",
        "Institute of Geophysics, University of Tehran"
    ]
    
    print("\nSelect Fajr and Isha calculation method:")
    fajr_isha_idx = get_choice_input("", fajr_isha_methods)
    
    asr_methods = [
        "Shafi'i, Maliki, Ja'fari, and Hanbali (shadow factor = 1)",
        "Hanafi (shadow factor = 2)"
    ]
    
    print("\nSelect Asr calculation method:")
    asr_idx = get_choice_input("", asr_methods)
    
    # Get date range
    print("\n--- Date Range ---")
    start_date = get_date_input("Start date (YYYY-MM-DD): ")
    end_date = get_date_input("End date (YYYY-MM-DD): ")
    
    if end_date < start_date:
        print("Error: End date must be after start date.")
        return
    
    # Initialize PrayTimes
    pt = PrayTimes()
    
    # Define calculation method parameters manually
    # These are the standard parameters for each method
    method_params = {
        0: {'fajr': 16, 'isha': 14, 'maghrib': '0 min', 'midnight': 'Jafari'},  # Jafari
        1: {'fajr': 18, 'isha': 18, 'maghrib': '0 min', 'midnight': 'Standard'},  # Karachi
        2: {'fajr': 15, 'isha': 15, 'maghrib': '0 min', 'midnight': 'Standard'},  # ISNA
        3: {'fajr': 18, 'isha': 17, 'maghrib': '0 min', 'midnight': 'Standard'},  # MWL
        4: {'fajr': 18.5, 'isha': '90 min', 'maghrib': '0 min', 'midnight': 'Standard'},  # Makkah
        5: {'fajr': 19.5, 'isha': 17.5, 'maghrib': '0 min', 'midnight': 'Standard'},  # Egypt
        6: {'fajr': 17.7, 'isha': 14, 'maghrib': 4.5, 'midnight': 'Jafari'}  # Tehran
    }
    
    # Apply the selected method parameters
    pt.adjust(method_params[fajr_isha_idx])
    
    # Set Asr method (Hanafi uses shadow factor of 2)
    if asr_idx == 1:  # Hanafi
        pt.adjust({'asr': 'Hanafi'})
    
    # Calculate prayer times for date range
    print("\nCalculating prayer times...")
    
    prayer_data = []
    prayer_data.append(['Prayer Name','Time and Date','Month'])
    current_date = start_date
    
    while current_date <= end_date:
        # Get timezone offset for this specific date (handles DST)
        tz_offset = get_timezone_offset(current_date)
        
        # Get prayer times for this date
        times = pt.getTimes(
            (current_date.year, current_date.month, current_date.day),
            (latitude, longitude),
            tz_offset
        )
        
        # Get Hijri month
        hijri_month = get_hijri_month_name(current_date)
        
        # Format times and add to data
        date_str = current_date.strftime("%Y-%m-%d")
        
        # Extract prayer times in order (excluding sunrise)
        prayers = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']
        prayer_names = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha']
        
        for prayer_key, prayer_name in zip(prayers, prayer_names):
            time_str = times[prayer_key]
            # Ensure 24-hour format with proper zero-padding
            try:
                # Parse the time (it's already in 24-hour format from praytimes)
                time_parts = time_str.split(':')
                hours = int(time_parts[0])
                minutes = int(time_parts[1])
                # Format to ensure HH:MM:SS format
                datetime_str = f"{date_str} {hours:02d}:{minutes:02d}:00"
            except:
                datetime_str = f"{date_str} {time_str}:00"
            
            prayer_data.append([prayer_name, datetime_str, hijri_month])
        
        current_date += timedelta(days=1)
    
    # Write to CSV
    with open('prayer_times.csv', 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        # No header as per requirements
        writer.writerows(prayer_data)
    
    print(f"\n✓ Successfully calculated {len(prayer_data)} prayer times")
    print(f"  Date range: {start_date.date()} to {end_date.date()}")
    print(f"  Total days: {(end_date - start_date).days + 1}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nOperation cancelled by user.")
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
