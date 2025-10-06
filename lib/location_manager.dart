import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'work_session_manager.dart';

class LocationManager {
  static const String _workLatitudeKey = 'work_latitude';
  static const String _workLongitudeKey = 'work_longitude';
  static const String _workAddressKey = 'work_address';
  static const String _autoTrackingEnabledKey = 'auto_tracking_enabled';
  static const double _geofenceRadius = 100.0; // 100 meters radius

  final WorkSessionManager _sessionManager;
  bool _isAutoTrackingEnabled = false;
  bool _isMonitoring = false;
  String? _workAddress;
  double? _workLatitude;
  double? _workLongitude;
  
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _wasInsideGeofence = false;

  LocationManager(this._sessionManager);

  // Check and request location permissions
  Future<bool> _checkLocationPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    
    return permission == LocationPermission.whileInUse || 
           permission == LocationPermission.always;
  }

  // Set work location
  Future<void> setWorkLocation(double latitude, double longitude, String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_workLatitudeKey, latitude);
    await prefs.setDouble(_workLongitudeKey, longitude);
    await prefs.setString(_workAddressKey, address);
    
    _workLatitude = latitude;
    _workLongitude = longitude;
    _workAddress = address;
    
    if (_isAutoTrackingEnabled) {
      await stopMonitoring();
      await startMonitoring();
    }
  }

  // Get work location
  Future<Map<String, dynamic>?> getWorkLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_workLatitudeKey);
    final lng = prefs.getDouble(_workLongitudeKey);
    final address = prefs.getString(_workAddressKey);
    
    if (lat != null && lng != null) {
      _workLatitude = lat;
      _workLongitude = lng;
      _workAddress = address;
      
      return {
        'latitude': lat,
        'longitude': lng,
        'address': address,
      };
    }
    return null;
  }

  // Enable/disable auto tracking
  Future<void> setAutoTrackingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoTrackingEnabledKey, enabled);
    _isAutoTrackingEnabled = enabled;
    
    if (enabled) {
      await startMonitoring();
    } else {
      await stopMonitoring();
    }
  }

  // Check if auto tracking is enabled
  Future<bool> isAutoTrackingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _isAutoTrackingEnabled = prefs.getBool(_autoTrackingEnabledKey) ?? false;
    return _isAutoTrackingEnabled;
  }

  // Get current location (simplified without address)
  Future<Map<String, dynamic>?> getCurrentLocation() async {
    try {
      if (!await _checkLocationPermissions()) {
        throw Exception('Location permissions denied');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': DateTime.now(),
      };
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  // Start monitoring location
  Future<void> startMonitoring() async {
    if (!await _checkLocationPermissions()) {
      throw Exception('Location permissions required for auto tracking');
    }

    final workLocation = await getWorkLocation();
    if (workLocation == null) {
      throw Exception('Work location not set');
    }

    if (_isMonitoring) {
      await stopMonitoring();
    }

    try {
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        _handleLocationUpdate(position);
      });

      _isMonitoring = true;
      print('Started monitoring work location');
      
      // Check initial location
      final currentLocation = await getCurrentLocation();
      if (currentLocation != null) {
        await _checkGeofenceStatus(
          currentLocation['latitude']!,
          currentLocation['longitude']!,
        );
      }
    } catch (e) {
      print('Error starting location monitoring: $e');
      throw e;
    }
  }

  // Stop monitoring location
  Future<void> stopMonitoring() async {
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _isMonitoring = false;
    _wasInsideGeofence = false;
    print('Stopped monitoring work location');
  }

  // Handle location updates
  void _handleLocationUpdate(Position position) async {
    await _checkGeofenceStatus(position.latitude, position.longitude);
  }

  // Check if current location is within geofence
  Future<void> _checkGeofenceStatus(double currentLat, double currentLng) async {
    final workLocation = await getWorkLocation();
    if (workLocation == null) return;

    final distance = await Geolocator.distanceBetween(
      workLocation['latitude']!,
      workLocation['longitude']!,
      currentLat,
      currentLng,
    );

    final isInsideGeofence = distance <= _geofenceRadius;

    if (isInsideGeofence && !_wasInsideGeofence) {
      await _handleGeofenceEntry();
    } else if (!isInsideGeofence && _wasInsideGeofence) {
      await _handleGeofenceExit();
    }

    _wasInsideGeofence = isInsideGeofence;
  }

  // Handle entering geofence
  Future<void> _handleGeofenceEntry() async {
    print('Entered work location geofence');
    
    final ongoingSession = await _sessionManager.getOngoingSession();
    if (ongoingSession == null) {
      print('Auto-starting work session');
      await _sessionManager.startSession(isAuto: true);
    }
  }

  // Handle exiting geofence
  Future<void> _handleGeofenceExit() async {
    print('Exited work location geofence');
    
    final ongoingSession = await _sessionManager.getOngoingSession();
    if (ongoingSession != null) {
      print('Auto-stopping work session');
      await _sessionManager.stopSession();
    }
  }

  // Check if user is currently at work
  Future<bool> isAtWorkLocation() async {
    try {
      final currentLocation = await getCurrentLocation();
      final workLocation = await getWorkLocation();
      
      if (currentLocation == null || workLocation == null) {
        return false;
      }

      final distance = await Geolocator.distanceBetween(
        workLocation['latitude']!,
        workLocation['longitude']!,
        currentLocation['latitude']!,
        currentLocation['longitude']!,
      );

      return distance <= _geofenceRadius;
    } catch (e) {
      print('Error checking if at work location: $e');
      return false;
    }
  }

  // Calculate distance to work location
  Future<double?> getDistanceToWork() async {
    try {
      final currentLocation = await getCurrentLocation();
      final workLocation = await getWorkLocation();
      
      if (currentLocation == null || workLocation == null) {
        return null;
      }

      return await Geolocator.distanceBetween(
        workLocation['latitude']!,
        workLocation['longitude']!,
        currentLocation['latitude']!,
        currentLocation['longitude']!,
      );
    } catch (e) {
      print('Error calculating distance to work: $e');
      return null;
    }
  }

  // Clean up
  void dispose() {
    stopMonitoring();
  }
}