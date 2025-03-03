import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class CustomerDashboard extends StatefulWidget {
  final String userId;
  const CustomerDashboard({super.key, required this.userId});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _orders = [];
  final _deliveryAddressController = TextEditingController();
  bool _isTracking = false;
  Timer? _trackingTimer;
  Map<String, String> _deliveryEstimates = {};
  Map<String, double> _deliveryProgress = {};
  DateTime? _selectedDeliveryDate;
  TimeOfDay? _selectedDeliveryTime;
  List<Map<String, dynamic>> _warehouses = [];
  Map<String, dynamic>? _selectedWarehouse;
  final MapController _mapController = MapController();
  bool _showSatellite = false;
  bool _isMapLoading = true;

  @override
  void initState() {
    super.initState();
    _isMapLoading = true;
    _initializeData();
    _fetchWarehouses();
    _startTrackingUpdates();
  }

  Future<void> _initializeData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final ordersResponse = await Supabase.instance.client
          .from('orders')
          .select('''
            *,
            warehouse:warehouse_id(
              id,
              warehouse_name,
              address
            ),
            driver:driver_id(
              id,
              full_name,
              phone_number
            )
          ''')
          .eq('customer_id', widget.userId)
          .order('created_at', ascending: false);

      print('Orders Response: $ordersResponse'); // Debug log

      setState(() {
        _orders = List<Map<String, dynamic>>.from(ordersResponse);
        _isLoading = false;
        _isTracking = true;
      });

      // Debug log each order's status
      for (var order in _orders) {
        print('Order ID: ${order['id']}, Status: ${order['status']}, Driver: ${order['driver']}');
      }

    } catch (e) {
      print('Error in _initializeData: $e');
      setState(() {
        _errorMessage = 'Failed to initialize: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchWarehouses() async {
    try {
      final response = await Supabase.instance.client
          .from('warehouse_details')
          .select('id, warehouse_name, address, latitude, longitude');
      
      setState(() {
        _warehouses = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      print('Error fetching warehouses: $e');
    }
  }

  void _startTrackingUpdates() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isTracking) {
        _updateDeliveryStatus();
      }
    });
  }

  Future<void> _updateDeliveryStatus() async {
    try {
      final inProgressOrders = _orders.where((o) => 
        o['status'] == 'in_progress' || o['status'] == 'at_warehouse'
      ).toList();
      
      for (var order in inProgressOrders) {
        final trackingData = await Supabase.instance.client
            .rpc('get_order_tracking', params: {'order_id': order['id']})
            .single();

        if (mounted) {
          setState(() {
            final index = _orders.indexWhere((o) => o['id'] == order['id']);
            if (index != -1) {
              // Update order with tracking information
              _orders[index] = {
                ..._orders[index],
                'current_latitude': trackingData['current_lat'],
                'current_longitude': trackingData['current_lng'],
                'estimated_delivery_time': trackingData['estimated_delivery'],
                'tracking_history': trackingData['tracking_history'],
              };

              // Calculate delivery progress and estimates
              if (trackingData['estimated_delivery'] != null) {
                final estimatedDelivery = DateTime.parse(trackingData['estimated_delivery']);
                final now = DateTime.now();
                final totalDuration = estimatedDelivery.difference(
                  DateTime.parse(order['created_at'])
                );
                final remainingDuration = estimatedDelivery.difference(now);
                
                if (remainingDuration.inMinutes > 0) {
                  _deliveryEstimates[order['id']] = _formatEstimatedTime(
                    remainingDuration.inMinutes
                  );
                  _deliveryProgress[order['id']] = 1 - (
                    remainingDuration.inMinutes / totalDuration.inMinutes
                  );
                }
              }
            }
          });
        }
      }
    } catch (e) {
      print('Error updating delivery status: $e');
    }
  }

  String _formatEstimatedTime(int minutes) {
    if (minutes < 60) {
      return '$minutes minutes';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '$hours h ${remainingMinutes} min';
  }

  Future<void> _updateDeliveryRating(String orderId, double rating) async {
    try {
      // First check if the rating column exists
      final response = await Supabase.instance.client
          .from('orders')
          .select('id')
          .eq('id', orderId)
          .single();

      if (response != null) {
        // Update using RPC call instead of direct column update
        await Supabase.instance.client
            .rpc('update_order_rating', params: {
              'order_id': orderId,
              'rating_value': rating,
            });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thank you for your rating!')),
          );
        }
      }
    } catch (e) {
      print('Error updating rating: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update rating at this time'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showScheduleDeliveryDialog() async {
    setState(() {
      _selectedWarehouse = null;
      _selectedDeliveryDate = null;
      _selectedDeliveryTime = null;
      _deliveryAddressController.clear();
    });

    await _showWarehouseSelectionDialog();

    if (_selectedWarehouse != null && mounted) {
      final DateTime now = DateTime.now();
      final DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: now.add(const Duration(days: 1)),
        firstDate: now,
        lastDate: now.add(const Duration(days: 14)),
        helpText: 'Select Delivery Date',
      );

      if (pickedDate != null && mounted) {
        final TimeOfDay? pickedTime = await showTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 9, minute: 0),
          helpText: 'Select Delivery Time',
        );

        if (pickedTime != null && mounted) {
          setState(() {
            _selectedDeliveryDate = DateTime(
              pickedDate.year,
              pickedDate.month,
              pickedDate.day,
              pickedTime.hour,
              pickedTime.minute,
            );
            _selectedDeliveryTime = pickedTime;
          });

          _showDeliveryConfirmationDialog();
        }
      }
    }
  }

  Future<void> _showWarehouseSelectionDialog() async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Warehouse'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _warehouses.length,
              itemBuilder: (context, index) {
                final warehouse = _warehouses[index];
                return ListTile(
                  title: Text(warehouse['warehouse_name']),
                  subtitle: Text(warehouse['address']),
                  onTap: () {
                    setState(() {
                      _selectedWarehouse = warehouse;
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDeliveryConfirmationDialog() async {
    final formattedDate = DateFormat('MMM dd, yyyy').format(_selectedDeliveryDate!);
    final formattedTime = _selectedDeliveryTime!.format(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delivery Schedule'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('From: ${_selectedWarehouse!['warehouse_name']}'),
                const SizedBox(height: 8),
                Text('Date: $formattedDate'),
                const SizedBox(height: 8),
                Text('Time: $formattedTime'),
                const SizedBox(height: 16),
                TextField(
                  controller: _deliveryAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Delivery Address',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _scheduleDelivery({}),
              child: const Text('Confirm Schedule'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _scheduleDelivery(Map<String, dynamic> order) async {
    try {
      if (_deliveryAddressController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter delivery address')),
        );
        return;
      }

      final scheduledTime = _selectedDeliveryDate!.toIso8601String();

      await Supabase.instance.client.from('orders').insert({
        'customer_id': widget.userId,
        'warehouse_id': _selectedWarehouse!['id'],
        'delivery_address': _deliveryAddressController.text,
        'scheduled_delivery': scheduledTime,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
        'pickup_latitude': _selectedWarehouse!['latitude'],
        'pickup_longitude': _selectedWarehouse!['longitude'],
        'delivery_latitude': 0.0,
        'delivery_longitude': 0.0,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery scheduled successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _deliveryAddressController.clear();
        _initializeData();
      }
    } catch (e) {
      print('Error scheduling delivery: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to schedule delivery: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'] ?? 'pending';
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
      case 'in_progress':
        statusColor = Colors.orange;
        statusIcon = Icons.local_shipping;
      case 'at_warehouse':
        statusColor = Colors.blue;
        statusIcon = Icons.warehouse;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.pending;
    }

    final bool isScheduled = order['scheduled_delivery'] != null;
    final bool canTrack = status == 'in_progress' || status == 'at_warehouse';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: statusColor.withOpacity(0.1),
              child: Icon(statusIcon, color: statusColor),
            ),
            title: Text(
              'Order #${order['id'].toString().substring(0, 8)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: ${status.toUpperCase()}',
                  style: TextStyle(color: statusColor),
                ),
                if (isScheduled)
                  Text(
                    'Scheduled: ${DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.parse(order['scheduled_delivery']))}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
              ],
            ),
            trailing: _buildOrderMenu(order),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('From:', order['warehouse']?['warehouse_name'] ?? 'Not assigned'),
                const SizedBox(height: 8),
                _buildInfoRow('To:', order['delivery_address'] ?? 'Not set'),
                const SizedBox(height: 8),

                // Action Buttons
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Show Track button for trackable orders
                    if (canTrack)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _trackDelivery(order),
                          icon: const Icon(Icons.location_on),
                          label: const Text('Track Order'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    
                    // Show Contact Driver button if driver is assigned
                    if (canTrack && order['driver'] != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _contactDriver(order['driver']),
                          icon: const Icon(Icons.phone),
                          label: const Text('Contact Agent'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                    
                    // Show Schedule button only if not scheduled yet
                    if (status == 'pending' && !isScheduled)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _scheduleDelivery(order),
                          icon: const Icon(Icons.schedule),
                          label: const Text('Schedule'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    
                    // Show Cancel button for pending orders
                    if (status == 'pending')
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _cancelOrder(order),
                          icon: const Icon(Icons.cancel),
                          label: const Text('Cancel'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                  ],
                ),

                // Show tracking information for in-progress orders
                if (canTrack) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Delivery Progress',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _deliveryProgress[order['id']] ?? 0.0,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ETA: ${_deliveryEstimates[order['id']] ?? 'Calculating...'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],

                // Rating for completed orders
                if (status == 'completed') ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Rate delivery: '),
                      RatingBar.builder(
                        initialRating: order['rating']?.toDouble() ?? 0.0,
                        minRating: 1,
                        direction: Axis.horizontal,
                        itemCount: 5,
                        itemSize: 24,
                        onRatingUpdate: (rating) {
                          _updateDeliveryRating(order['id'], rating);
                        },
                        itemBuilder: (context, _) => const Icon(
                          Icons.star,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderMenu(Map<String, dynamic> order) {
    return PopupMenuButton<String>(
      onSelected: (String choice) async {
        switch (choice) {
          case 'make_in_progress':
            await _updateOrderStatus(order['id'], 'in_progress');
            break;
          case 'make_at_warehouse':
            await _updateOrderStatus(order['id'], 'at_warehouse');
            break;
          case 'reschedule':
            _rescheduleDelivery(order);
            break;
          case 'track':
            _trackDelivery(order);
            break;
          case 'cancel':
            _cancelOrder(order);
            break;
        }
      },
      itemBuilder: (BuildContext context) {
        final List<PopupMenuEntry<String>> items = [];
        
        if (order['status'] == 'pending') {
          items.addAll([
            const PopupMenuItem<String>(
              value: 'make_in_progress',
              child: Text('Set In Progress (Test)'),
            ),
            const PopupMenuItem<String>(
              value: 'make_at_warehouse',
              child: Text('Set At Warehouse (Test)'),
            ),
            const PopupMenuItem<String>(
              value: 'reschedule',
              child: Text('Reschedule'),
            ),
            const PopupMenuItem<String>(
              value: 'cancel',
              child: Text('Cancel Order'),
            ),
          ]);
        }
        
        if (order['status'] == 'in_progress' || order['status'] == 'at_warehouse') {
          items.add(
            const PopupMenuItem<String>(
              value: 'track',
              child: Text('Track Order'),
            ),
          );
        }
        
        return items;
      },
    );
  }

  Future<void> _rescheduleDelivery(Map<String, dynamic> order) async {
    final DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 14)),
    );

    if (newDate != null && mounted) {
      final TimeOfDay? newTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (newTime != null && mounted) {
        try {
          final newScheduledTime = DateTime(
            newDate.year,
            newDate.month,
            newDate.day,
            newTime.hour,
            newTime.minute,
          ).toIso8601String();

          await Supabase.instance.client
              .from('orders')
              .update({'scheduled_delivery': newScheduledTime})
              .eq('id', order['id']);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Delivery rescheduled successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            _initializeData(); // Refresh the orders
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to reschedule: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _trackDelivery(Map<String, dynamic> order) async {
    if (order['delivery_latitude'] == null || order['delivery_longitude'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery location not available')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Live Tracking',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildMapSection(order),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapSection(Map<String, dynamic> order) {
    final deliveryLocation = LatLng(
      double.parse(order['delivery_latitude'].toString()),
      double.parse(order['delivery_longitude'].toString())
    );

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            center: deliveryLocation,
            zoom: 13,
            minZoom: 3,
            maxZoom: 18,
            onMapReady: () {
              setState(() {
                _isMapLoading = false;
              });
            },
          ),
          children: [
            // Base map layer with error handling
            TileLayer(
              urlTemplate: _showSatellite
                  ? 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}'  // Google Satellite
                  : 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', // Google Streets
              userAgentPackageName: 'com.example.app',
              backgroundColor: Colors.grey[200],
              // Add error handling for tiles
              errorImage: const NetworkImage(
                'https://cdn.jsdelivr.net/gh/opensourcemap/map-tiles@1.0.0/error.png'
              ),
              // Add tile loading error handler
              errorTileCallback: (tile, error, stackTrace) {
                print('Error loading tile: $error');
                // Attempt to reload the tile after a delay
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() {});
                  }
                });
              },
              // Add additional options for better performance
              keepBuffer: 5,
              tileProvider: NetworkTileProvider(),
            ),
            // Delivery route if available
            if (order['current_latitude'] != null && order['current_longitude'] != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [
                      LatLng(
                        double.parse(order['current_latitude'].toString()),
                        double.parse(order['current_longitude'].toString())
                      ),
                      deliveryLocation,
                    ],
                    color: Theme.of(context).primaryColor,
                    strokeWidth: 4,
                  ),
                ],
              ),
            // Markers layer
            MarkerLayer(
              markers: [
                // Driver's current location marker (if available)
                if (order['current_latitude'] != null && order['current_longitude'] != null)
                  Marker(
                    point: LatLng(
                      double.parse(order['current_latitude'].toString()),
                      double.parse(order['current_longitude'].toString())
                    ),
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
                            color: Colors.blue[700],
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Driver',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.local_shipping,
                          color: Colors.blue,
                          size: 30,
                          shadows: [
                            Shadow(
                              color: Colors.white,
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                // Delivery location marker
                Marker(
                  point: deliveryLocation,
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
                            color: Theme.of(context).primaryColor,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Delivery',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.location_on,
                        color: Theme.of(context).primaryColor,
                        size: 30,
                        shadows: const [
                          Shadow(
                            color: Colors.white,
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        // Loading indicator
        if (_isMapLoading)
          Container(
            color: Colors.white.withOpacity(0.8),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        // Map controls
        Positioned(
          right: 16,
          top: 16,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          icon: Icon(
                            _showSatellite ? Icons.map : Icons.satellite,
                            color: Theme.of(context).primaryColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _showSatellite = !_showSatellite;
                            });
                          },
                          tooltip: _showSatellite ? 'Show Map' : 'Show Satellite',
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          icon: Icon(
                            Icons.my_location,
                            color: Theme.of(context).primaryColor,
                          ),
                          onPressed: () {
                            _mapController.move(deliveryLocation, 15);
                          },
                          tooltip: 'Center Map',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Error message if needed
        if (_errorMessage != null)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cancel Order'),
          content: const Text('Are you sure you want to cancel this order?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    ) ?? false;

    if (confirm && mounted) {
      try {
        await Supabase.instance.client
            .from('orders')
            .update({'status': 'cancelled'})
            .eq('id', order['id']);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order cancelled successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _initializeData(); // Refresh the orders
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to cancel order: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value ?? 'N/A',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _contactDriver(Map<String, dynamic> driver) async {
    final phoneNumber = driver['phone_number'];
    if (phoneNumber != null) {
      final url = 'tel:$phoneNumber';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      }
    }
  }

  Future<void> _updateOrderStatus(String orderId, String status) async {
    try {
      await Supabase.instance.client
          .from('orders')
          .update({
            'status': status,
            'driver_id': 'f9bed83f-3c51-4195-8db2-4e4c1a26c5f3', // Example driver ID from schema
          })
          .eq('id', orderId);

      // Refresh the orders
      await _initializeData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order status updated to $status')),
        );
      }
    } catch (e) {
      print('Error updating order status: $e');
    }
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _deliveryAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initializeData,
          ),
        ],
      ),
      body: _errorMessage != null
          ? Center(
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
            )
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orders.length,
                  itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showScheduleDeliveryDialog,
        label: const Text('Schedule Delivery'),
        icon: const Icon(Icons.add),
      ),
    );
  }
} 