import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';

class WarehouseDashboard extends StatefulWidget {
  final String userId;
  const WarehouseDashboard({super.key, required this.userId});

  @override
  State<WarehouseDashboard> createState() => _WarehouseDashboardState();
}

class _WarehouseDashboardState extends State<WarehouseDashboard> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _warehouseDetails;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _availableDrivers = [];
  final MapController _mapController = MapController();
  bool _showMap = true;
  Timer? _locationUpdateTimer;
  Map<String, LatLng> _driverLocations = {};
  bool _trackDrivers = false;
  Map<String, dynamic> _efficiencyMetrics = {
    'avgDeliveryTime': 0.0,
    'fuelEfficiency': 0.0,
    'customerSatisfaction': 0.0,
  };

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Fetch warehouse details with coordinates
      final warehouseResponse = await Supabase.instance.client
          .from('warehouse_details')
          .select('*, users!inner(*)')
          .eq('user_id', widget.userId)
          .single();

      // Fetch orders for this warehouse
      final ordersResponse = await Supabase.instance.client
          .from('orders')
          .select('''
            *,
            driver:driver_id(
              id,
              full_name,
              driver_details(*)
            )
          ''')
          .eq('warehouse_id', warehouseResponse['id'])
          .order('created_at', ascending: false);

      // Fetch available drivers
      final driversResponse = await Supabase.instance.client
          .from('users')
          .select('''
            *,
            driver_details(*),
            driver_locations(
              latitude,
              longitude,
              updated_at
            )
          ''')
          .eq('role', 'driver');

      setState(() {
        _warehouseDetails = warehouseResponse;
        _orders = List<Map<String, dynamic>>.from(ordersResponse);
        _availableDrivers = List<Map<String, dynamic>>.from(driversResponse);
        _isLoading = false;
      });

      // Initialize driver locations
      _updateDriverLocations();

    } catch (e) {
      print('Error in _initializeData: $e');
      setState(() {
        _errorMessage = 'Failed to initialize: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateDriverLocations() async {
    try {
      // Get list of driver IDs from orders
      final driverIds = _orders
          .map((o) => o['driver_id'])
          .where((id) => id != null)
          .toList();

      if (driverIds.isEmpty) return;

      final locationsResponse = await Supabase.instance.client
          .from('driver_locations')
          .select('driver_id, latitude, longitude')
          .inFilter('driver_id', driverIds);

      setState(() {
        for (final location in locationsResponse) {
          _driverLocations[location['driver_id']] = LatLng(
            location['latitude'],
            location['longitude'],
          );
        }
      });
    } catch (e) {
      print('Error updating driver locations: $e');
    }
  }

  void _toggleDriverTracking() {
    setState(() {
      _trackDrivers = !_trackDrivers;
      if (_trackDrivers) {
        _locationUpdateTimer = Timer.periodic(
          const Duration(seconds: 30),
          (_) => _updateDriverLocations(),
        );
      } else {
        _locationUpdateTimer?.cancel();
        _locationUpdateTimer = null;
      }
    });
  }

  Future<void> _assignDriver(String orderId, String driverId) async {
    try {
      await Supabase.instance.client
          .from('orders')
          .update({'driver_id': driverId})
          .eq('id', orderId);

      // Refresh orders
      _initializeData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to assign driver: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Warehouse Dashboard')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ElevatedButton(
                onPressed: _initializeData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading || _warehouseDetails == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isSmallScreen = MediaQuery.of(context).size.width < 900;
    
    final warehouseLocation = LatLng(
      _warehouseDetails!['latitude'] is String 
          ? double.parse(_warehouseDetails!['latitude']) 
          : _warehouseDetails!['latitude']?.toDouble() ?? 0.0,
      _warehouseDetails!['longitude'] is String 
          ? double.parse(_warehouseDetails!['longitude']) 
          : _warehouseDetails!['longitude']?.toDouble() ?? 0.0,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_warehouseDetails!['warehouse_name']),
        actions: [
          IconButton(
            icon: Icon(_trackDrivers ? Icons.location_on : Icons.location_off),
            onPressed: _toggleDriverTracking,
            tooltip: _trackDrivers ? 'Stop Tracking' : 'Track Drivers',
          ),
          if (isSmallScreen)
            IconButton(
              icon: Icon(_showMap ? Icons.list : Icons.map),
              onPressed: () {
                setState(() {
                  _showMap = !_showMap;
                });
              },
              tooltip: _showMap ? 'Show Orders' : 'Show Map',
            ),
        ],
      ),
      body: SafeArea(
        child: isSmallScreen
            ? _showMap
                ? _buildMapSection(warehouseLocation)
                : _buildOrdersList()
            : Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildOrdersList(),
                  ),
                  Expanded(
                    flex: 3,
                    child: _buildMapSection(warehouseLocation),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildOrdersList() {
    return Container(
      color: Colors.grey[100],
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text(
                  'Orders',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_orders.length} Total',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Orders List
          Expanded(
            child: _orders.isEmpty
                ? const Center(
                    child: Text('No orders available'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) {
                      final order = _orders[index];
                      final hasDriver = order['driver_id'] != null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          title: Text(
                            'Order #${order['id'].toString().substring(0, 8)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            hasDriver ? 'Assigned' : 'Pending Assignment',
                            style: TextStyle(
                              color: hasDriver ? Colors.green : Colors.orange,
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Delivery Address: ${order['delivery_address']}'),
                                  const SizedBox(height: 8),
                                  Text('Status: ${order['status']}'),
                                  const SizedBox(height: 16),
                                  if (!hasDriver) ...[
                                    const Text(
                                      'Assign Driver:',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 50,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _availableDrivers.length,
                                        itemBuilder: (context, driverIndex) {
                                          final driver = _availableDrivers[driverIndex];
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 8),
                                            child: ElevatedButton.icon(
                                              onPressed: () => _assignDriver(
                                                order['id'],
                                                driver['id'],
                                              ),
                                              icon: const Icon(Icons.person),
                                              label: Text(driver['full_name']),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                foregroundColor: Theme.of(context).primaryColor,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ] else ...[
                                    Text(
                                      'Assigned to: ${_availableDrivers.firstWhere(
                                        (d) => d['id'] == order['driver_id'],
                                        orElse: () => {'full_name': 'Unknown'},
                                      )['full_name']}',
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection(LatLng warehouseLocation) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            center: warehouseLocation,
            zoom: 13,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',  // Using OpenStreetMap for now
            ),
            MarkerLayer(
              markers: [
                // Warehouse marker
                Marker(
                  point: warehouseLocation,
                  width: 60,
                  height: 60,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Warehouse',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.warehouse,
                        color: Theme.of(context).primaryColor,
                        size: 30,
                      ),
                    ],
                  ),
                ),
                // Order markers
                ..._orders.map(
                  (order) {
                    // Fixed type conversion for order locations
                    final orderLat = order['delivery_latitude'] is String 
                        ? double.parse(order['delivery_latitude']) 
                        : order['delivery_latitude']?.toDouble() ?? 0.0;
                    final orderLng = order['delivery_longitude'] is String 
                        ? double.parse(order['delivery_longitude']) 
                        : order['delivery_longitude']?.toDouble() ?? 0.0;

                    return Marker(
                      point: LatLng(orderLat, orderLng),
                      width: 60,
                      height: 60,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: order['driver_id'] != null 
                                    ? Colors.green 
                                    : Colors.orange,
                              ),
                            ),
                            child: Text(
                              order['driver_id'] != null ? 'Assigned' : 'Pending',
                              style: TextStyle(
                                color: order['driver_id'] != null 
                                    ? Colors.green 
                                    : Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.location_on,
                            color: order['driver_id'] != null 
                                ? Colors.green 
                                : Colors.orange,
                            size: 30,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 16,
          top: 16,
          child: FloatingActionButton.small(
            onPressed: () {
              _mapController.move(warehouseLocation, 13);
            },
            child: const Icon(Icons.home),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsDashboard() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Performance Metrics',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricTile(
                'Avg Delivery Time',
                '${_efficiencyMetrics['avgDeliveryTime']} min',
                Icons.timer,
              ),
              _buildMetricTile(
                'Fuel Efficiency',
                '${_efficiencyMetrics['fuelEfficiency']} L/km',
                Icons.local_gas_station,
              ),
              _buildMetricTile(
                'Customer Satisfaction',
                '${_efficiencyMetrics['customerSatisfaction']}%',
                Icons.sentiment_satisfied,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
} 