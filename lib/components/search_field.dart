import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

typedef PlaceSelectedCallback = void Function(LatLng location, String description);

/// SearchField: a compact search textbox that expands on focus and shows
/// Google Places suggestions restricted to the Philippines.
class SearchField extends StatefulWidget {
  final double top;
  final double left;
  final PlaceSelectedCallback? onPlaceSelected;
  final VoidCallback? onFocusChanged; // Callback when focus changes

  const SearchField({Key? key, this.top = 50, this.left = 90, this.onPlaceSelected, this.onFocusChanged}) : super(key: key);

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _predictions = [];
  bool _loading = false;
  bool _isFocused = false;

  // sizing
  final double _baseHeight = 55.0;
  final double _itemHeight = 50.0;
  final double _maxMultiplier = 5.0; // max height = base * multiplier

  String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _focus.addListener(() {
      setState(() {
        _isFocused = _focus.hasFocus;
        if (!_isFocused) _predictions = [];
      });
      // Notify parent about focus change
      if (widget.onFocusChanged != null) {
        widget.onFocusChanged!();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {}); // trigger rebuild to show/hide clear button
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () => _doAutocomplete(v));
  }

  Future<void> _doAutocomplete(String input) async {
    final key = _apiKey;
    if (key.isEmpty) return;
    setState(() => _loading = true);

    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
      'input': input,
      'key': key,
      'language': 'en',
      'sessiontoken': DateTime.now().millisecondsSinceEpoch.toString(),
      // Restrict results to the Philippines
      'components': 'country:ph',
    });

    try {
      final res = await http.get(uri);
      final body = json.decode(res.body) as Map<String, dynamic>;
      final status = body['status'] as String? ?? '';
      if (status == 'OK') {
        final preds = (body['predictions'] as List<dynamic>?) ?? [];
        setState(() => _predictions = preds.map((p) => p as Map<String, dynamic>).toList());
      } else {
        final err = body['error_message'] as String?;
        if (err != null) debugPrint('Places API error: $err');
        setState(() => _predictions = []);
      }
    } catch (e) {
      debugPrint('Autocomplete failed: $e');
      setState(() => _predictions = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPrediction(Map<String, dynamic> pred) async {
    final key = _apiKey;
    if (key.isEmpty) return;
    final placeId = pred['place_id'] as String?;
    final description = pred['description'] as String? ?? '';
    if (placeId == null) return;

    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': placeId,
      'key': key,
      'fields': 'geometry',
    });

    try {
      final res = await http.get(uri);
      final body = json.decode(res.body) as Map<String, dynamic>;
      final status = body['status'] as String? ?? '';
      if (status == 'OK') {
        final result = body['result'] as Map<String, dynamic>;
        final geometry = result['geometry'] as Map<String, dynamic>;
        final loc = geometry['location'] as Map<String, dynamic>;
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        final latLng = LatLng(lat, lng);
        _ctrl.text = description;
        _predictions = [];
        _focus.unfocus();
        if (widget.onPlaceSelected != null) widget.onPlaceSelected!(latLng, description);
      }
    } catch (e) {
      debugPrint('Place details failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = _baseHeight * _maxMultiplier;

    double desiredHeight = _baseHeight;
    if (_isFocused && _predictions.isEmpty && !_loading && _ctrl.text.isNotEmpty) {
      // Add extra height for "No results" message
      desiredHeight = _baseHeight + 30;
    } else if (_predictions.isNotEmpty) {
      final suggestionsHeight = math.min((_predictions.length * _itemHeight), maxHeight - _baseHeight);
      desiredHeight = _baseHeight + suggestionsHeight;
    }

    // When focused, expand width and shift left so the box moves toward center
    final screenW = MediaQuery.of(context).size.width;
    final baseWidth = screenW - widget.left - 50;
    // expanded width: either 1.2x base or nearly full width leaving small margins
    final expandedWidth = math.min(screenW - 30, baseWidth * 1.2);
    final currentWidth = _isFocused ? expandedWidth : baseWidth;
    final currentLeft = _isFocused ? (screenW - currentWidth) / 2 : widget.left;

    return AnimatedPositioned(
      top: widget.top,
      left: currentLeft,
      width: currentWidth,
      height: desiredHeight,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: Column(
          children: [
            // Top row with icon + text field
            SizedBox(
              height: _baseHeight - 12,
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Icon(Icons.search, color: Colors.black),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      onChanged: _onChanged,
                      decoration: const InputDecoration(
                        hintText: 'Saan po tayo?',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 7),
                      ),
                    ),
                  ),
                  if (_ctrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        setState(() {
                          _ctrl.clear();
                          _predictions = [];
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  if (_loading) const Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ],
              ),
            ),

            // Suggestions area (scrollable when many)
            if (_predictions.isNotEmpty)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: _predictions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = _predictions[i];
                        final struct = p['structured_formatting'] as Map<String, dynamic>?;
                        final main = struct != null ? (struct['main_text'] as String? ?? '') : (p['description'] as String? ?? '');
                        final secondary = struct != null ? (struct['secondary_text'] as String? ?? '') : '';
                        return ListTile(
                          title: Text(main),
                          subtitle: secondary.isNotEmpty ? Text(secondary) : null,
                          dense: true,
                          onTap: () => _selectPrediction(p),
                        );
                      },
                    ),
                  ),
                ),
              )
            else if (!_loading && _ctrl.text.isNotEmpty && _isFocused)
              // small hint when focused but no results
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No results', style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
          ],
        ),
      ),
    );
  }
}