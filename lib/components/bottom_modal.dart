import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/upper_case_formatter.dart';

class BottomModal extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onExpandToggle; // not used but available
  final void Function(DragEndDetails) onVerticalDragEnd;
  final TextEditingController routeController;
  final TextEditingController passengersController;
  final FocusNode routeFocusNode;
  final FocusNode passengersFocusNode;
  final String autocompleteSuggestion;
  final VoidCallback onCompleteText;
  final VoidCallback onSubmit;

  const BottomModal({
    Key? key,
    required this.isExpanded,
    required this.onVerticalDragEnd,
    required this.routeController,
    required this.passengersController,
    required this.routeFocusNode,
    required this.passengersFocusNode,
    required this.autocompleteSuggestion,
    required this.onCompleteText,
    required this.onSubmit,
    required this.onExpandToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onVerticalDragEnd: onVerticalDragEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: isExpanded ? screenHeight * 0.38 : screenHeight * 0.09,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(40),
              topRight: Radius.circular(40),
            ),
          ),
          child: Column(
            children: [
              // Dragger Handle
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              // Content (TextFields and Button) - Only show when expanded
              if (isExpanded)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        SizedBox(
                          width: 280,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF4AB7E5),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // If no text, show hint
                                if (routeController.text.isEmpty && !routeFocusNode.hasFocus)
                                  const Center(
                                    child: Text(
                                      'CHOOSE ROUTE',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white70, fontSize: 16),
                                    ),
                                  ),

                                // Visible suggestion layer (typed + remaining suggestion)
                                if (routeFocusNode.hasFocus || routeController.text.isNotEmpty)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    child: RichText(
                                      textAlign: TextAlign.center,
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: routeController.text.toUpperCase(),
                                            style: const TextStyle(color: Colors.white, fontSize: 16),
                                          ),
                                          if (autocompleteSuggestion.isNotEmpty)
                                            TextSpan(
                                              text: autocompleteSuggestion
                                                  .substring(routeController.text.length)
                                                  .toUpperCase(),
                                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),

                                // Invisible TextField sits on top to capture input; cursor visible
                                TextField(
                                  controller: routeController,
                                  focusNode: routeFocusNode,
                                  textAlign: TextAlign.center,
                                  inputFormatters: [UpperCaseTextFormatter()],
                                  onSubmitted: (_) => onCompleteText(),
                                  cursorColor: Colors.white,
                                  decoration: const InputDecoration.collapsed(hintText: ''),
                                  style: const TextStyle(
                                    color: Colors.transparent,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Second TextField - Passengers (Numbers only)
                        SizedBox(
                          width: 280,
                          child: TextField(
                            controller: passengersController,
                            focusNode: passengersFocusNode,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              hintText: passengersFocusNode.hasFocus ? '' : 'MAX NO. OF PASSENGERS',
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
                              filled: true,
                              fillColor: const Color(0xFFF7B731),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),

                        // Button
                        SizedBox(
                          width: 180,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF007F3F),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            onPressed: onSubmit,
                            child: const Text(
                              'BIYAHE',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
