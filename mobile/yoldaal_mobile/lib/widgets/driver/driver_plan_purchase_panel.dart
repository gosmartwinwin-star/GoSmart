import 'package:flutter/material.dart';

import '../../application/driver_access/driver_plan_purchase_gateway.dart';
import '../../controllers/driver_plan_purchase_controller.dart';
import '../../domain/subscription/driver_pass_plan.dart';

class DriverPlanPurchasePanel extends StatefulWidget {
  const DriverPlanPurchasePanel({super.key, required this.controller});

  final DriverPlanPurchaseController controller;

  @override
  State<DriverPlanPurchasePanel> createState() =>
      _DriverPlanPurchasePanelState();
}

class _DriverPlanPurchasePanelState extends State<DriverPlanPurchasePanel> {
  final _checkoutFormKey = GlobalKey<FormState>();

  final _buyerNameController = TextEditingController();
  final _buyerSurnameController = TextEditingController();
  final _buyerIdentityNumberController = TextEditingController();
  final _buyerEmailController = TextEditingController();
  final _buyerRegistrationAddressController = TextEditingController();
  final _buyerCityController = TextEditingController();
  final _buyerCountryController = TextEditingController();
  final _buyerZipCodeController = TextEditingController();

  final _billingAddressController = TextEditingController();
  final _billingContactNameController = TextEditingController();
  final _billingCityController = TextEditingController();
  final _billingCountryController = TextEditingController();
  final _billingZipCodeController = TextEditingController();

  List<TextEditingController> get _checkoutInputControllers => [
    _buyerNameController,
    _buyerSurnameController,
    _buyerIdentityNumberController,
    _buyerEmailController,
    _buyerRegistrationAddressController,
    _buyerCityController,
    _buyerCountryController,
    _buyerZipCodeController,
    _billingAddressController,
    _billingContactNameController,
    _billingCityController,
    _billingCountryController,
    _billingZipCodeController,
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.loadCatalog();
    widget.controller.recoverLatestPaymentStatus();
  }

  @override
  void didUpdateWidget(covariant DriverPlanPurchasePanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      _clearCheckoutInput();
      widget.controller.loadCatalog();
      widget.controller.recoverLatestPaymentStatus();
    }
  }

  @override
  void dispose() {
    for (final controller in _checkoutInputControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearCheckoutInput() {
    for (final controller in _checkoutInputControllers) {
      controller.clear();
    }
  }

  String? _requiredCheckoutField(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Bu alan zorunludur.';
    }

    return null;
  }

  Widget _checkoutField({
    required Key key,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        key: key,
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
        validator: _requiredCheckoutField,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Future<void> _initializeCheckout() async {
    final valid = _checkoutFormKey.currentState?.validate() ?? false;

    if (!valid) {
      return;
    }

    final controller = widget.controller;

    await controller.initializeCheckout(
      buyer: DriverPlanCheckoutBuyer(
        name: _buyerNameController.text.trim(),
        surname: _buyerSurnameController.text.trim(),
        identityNumber: _buyerIdentityNumberController.text.trim(),
        email: _buyerEmailController.text.trim(),
        registrationAddress: _buyerRegistrationAddressController.text.trim(),
        city: _buyerCityController.text.trim(),
        country: _buyerCountryController.text.trim(),
        zipCode: _buyerZipCodeController.text.trim(),
      ),
      billingAddress: DriverPlanCheckoutBillingAddress(
        address: _billingAddressController.text.trim(),
        contactName: _billingContactNameController.text.trim(),
        city: _billingCityController.text.trim(),
        country: _billingCountryController.text.trim(),
        zipCode: _billingZipCodeController.text.trim(),
      ),
    );

    if (!mounted) {
      return;
    }

    if (controller.paymentPageReady) {
      _clearCheckoutInput();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final catalog = controller.catalog;
        final prepared = controller.prepared;
        final paymentPageLaunchErrorMessage =
            controller.paymentPageLaunchErrorMessage;
        final paymentStatusOutcome =
            controller.paymentStatus?.outcome;
        final paymentStatusErrorMessage =
            controller.paymentStatusErrorMessage;
        final paymentStatusTerminal =
            paymentStatusOutcome ==
                DriverPlanPaymentOutcome.paymentFailed ||
            paymentStatusOutcome ==
                DriverPlanPaymentOutcome.settled;
        final showPaymentStatusSurface =
            controller.paymentPageReady ||
            controller.paymentStatus != null ||
            paymentStatusErrorMessage != null ||
            controller.paymentStatusRefreshing;
        final paymentStatusRefreshAvailable =
            controller.initializedCheckout != null ||
            controller.paymentStatus != null;

        return Card(
          key: const ValueKey('driver-plan-purchase-panel'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sürücü kontör planı',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Kullanılabilir planlar YoldaAl sunucusundan alınır.',
                ),
                const SizedBox(height: 12),
                if (controller.catalogLoading && catalog == null)
                  const Center(
                    child: CircularProgressIndicator(
                      key: ValueKey('driver-plan-catalog-loading'),
                      strokeWidth: 2,
                    ),
                  )
                else if (catalog == null) ...[
                  Text(
                    controller.catalogErrorMessage ??
                        'Plan seçenekleri yüklenemedi.',
                    key: const ValueKey('driver-plan-catalog-error'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('driver-plan-catalog-retry'),
                    onPressed: controller.catalogLoading
                        ? null
                        : controller.loadCatalog,
                    child: const Text('Planları Tekrar Dene'),
                  ),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in catalog.plans)
                        ChoiceChip(
                          key: ValueKey('driver-plan-${entry.plan.name}'),
                          label: Text(entry.plan.displayName),
                          selected: controller.selectedPlan == entry.plan,
                          onSelected:
                              entry.enabled &&
                                  !controller.preparing &&
                                  prepared == null
                              ? (selected) {
                                  if (selected) {
                                    controller.selectPlan(entry.plan);
                                  }
                                }
                              : null,
                        ),
                    ],
                  ),
                  if (catalog.plans.any((entry) => !entry.enabled)) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Kullanılamayan planlar sunucu kataloğuna göre devre dışıdır.',
                      key: ValueKey('driver-plan-catalog-disabled-note'),
                    ),
                  ],
                  if (controller.errorMessage case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      key: const ValueKey('driver-plan-purchase-error'),
                    ),
                  ],
                  if (prepared != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${prepared.plan.displayName} plan talebi hazırlandı.',
                      key: const ValueKey('driver-plan-purchase-prepared'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Ödeme veya paket aktivasyonu henüz tamamlanmadı.',
                    ),
                  ],
                  if (showPaymentStatusSurface) ...[
                    const SizedBox(height: 12),
                    if (controller.paymentStatusRefreshing)
                      const Center(
                        child: CircularProgressIndicator(
                          key: ValueKey(
                            'driver-plan-payment-status-loading',
                          ),
                          strokeWidth: 2,
                        ),
                      ),
                    if (paymentStatusOutcome ==
                        DriverPlanPaymentOutcome.pending)
                      const Text(
                        '\u00d6deme sonucu bekleniyor.',
                        key: ValueKey(
                          'driver-plan-payment-status-pending',
                        ),
                      ),
                    if (paymentStatusOutcome ==
                        DriverPlanPaymentOutcome.paymentReview)
                      const Text(
                        '\u00d6deme incelemede. '
                        'Durumu daha sonra tekrar kontrol edin.',
                        key: ValueKey(
                          'driver-plan-payment-status-review',
                        ),
                      ),
                    if (paymentStatusOutcome ==
                        DriverPlanPaymentOutcome.paymentFailed)
                      const Text(
                        '\u00d6deme ba\u015far\u0131s\u0131z.',
                        key: ValueKey(
                          'driver-plan-payment-status-failure',
                        ),
                      ),
                    if (paymentStatusOutcome ==
                        DriverPlanPaymentOutcome.settled)
                      const Text(
                        '\u00d6deme ba\u015far\u0131yla tamamland\u0131.',
                        key: ValueKey(
                          'driver-plan-payment-status-success',
                        ),
                      ),
                    if (paymentStatusErrorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        paymentStatusErrorMessage,
                        key: const ValueKey(
                          'driver-plan-payment-status-error',
                        ),
                      ),
                    ],
                    if (paymentStatusRefreshAvailable) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const ValueKey(
                          'driver-plan-payment-status-refresh',
                        ),
                        onPressed:
                            !controller.paymentStatusRefreshing &&
                                !paymentStatusTerminal
                            ? () {
                                controller.refreshPaymentStatus();
                              }
                            : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text(
                          '\u00d6deme Durumunu Kontrol Et',
                        ),
                      ),
                    ],
                  ],
                  if (prepared != null) ...[
                    const SizedBox(height: 16),
                    if (controller.paymentPageReady) ...[
                      const Text(
                        '\u00d6deme sayfas\u0131 haz\u0131r. '
                        'Harici taray\u0131c\u0131da devam edebilirsiniz.',
                        key: ValueKey('driver-plan-checkout-ready'),
                      ),
                    const SizedBox(height: 12),
                    if (paymentPageLaunchErrorMessage != null) ...[
                      Text(
                        paymentPageLaunchErrorMessage,
                        key: const ValueKey(
                          'driver-plan-checkout-launch-error',
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    FilledButton.icon(
                      key: const ValueKey(
                        'driver-plan-checkout-open',
                      ),
                      onPressed:
                          controller.paymentPageLaunchAvailable &&
                              !controller.paymentPageLaunching
                          ? () {
                              controller.launchPaymentPage();
                            }
                          : null,
                      icon: controller.paymentPageLaunching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.open_in_new),
                      label: Text(
                        controller.paymentPageLaunching
                            ? 'Ödeme Sayfası Açılıyor'
                            : 'Ödeme Sayfasını Aç',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Ödeme harici tarayıcıda devam eder. '
                      'Tarayıcıdan dönmek ödemenin tamamlandığı '
                      'anlamına gelmez.',
                      key: ValueKey(
                        'driver-plan-checkout-browser-note',
                      ),
                    ),

                    ] else ...[
                      Text(
                        '\u00d6deme bilgileri',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Bu bilgiler yaln\u0131zca \u00f6deme sayfas\u0131n\u0131 '
                        'haz\u0131rlamak i\u00e7in kullan\u0131l\u0131r.',
                        key: ValueKey('driver-plan-checkout-transient-note'),
                      ),
                      const SizedBox(height: 12),
                      Form(
                        key: _checkoutFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Al\u0131c\u0131 bilgileri',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            _checkoutField(
                              key: const ValueKey('driver-plan-buyer-name'),
                              label: 'Ad',
                              controller: _buyerNameController,
                            ),
                            _checkoutField(
                              key: const ValueKey('driver-plan-buyer-surname'),
                              label: 'Soyad',
                              controller: _buyerSurnameController,
                            ),
                            _checkoutField(
                              key: const ValueKey(
                                'driver-plan-buyer-identity-number',
                              ),
                              label: 'Kimlik numaras\u0131',
                              controller: _buyerIdentityNumberController,
                              keyboardType: TextInputType.number,
                            ),
                            _checkoutField(
                              key: const ValueKey('driver-plan-buyer-email'),
                              label: 'E-posta',
                              controller: _buyerEmailController,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            _checkoutField(
                              key: const ValueKey(
                                'driver-plan-buyer-registration-address',
                              ),
                              label: 'Kay\u0131t adresi',
                              controller: _buyerRegistrationAddressController,
                            ),
                            _checkoutField(
                              key: const ValueKey('driver-plan-buyer-city'),
                              label: '\u015eehir',
                              controller: _buyerCityController,
                            ),
                            _checkoutField(
                              key: const ValueKey('driver-plan-buyer-country'),
                              label: '\u00dclke',
                              controller: _buyerCountryController,
                            ),
                            _checkoutField(
                              key: const ValueKey('driver-plan-buyer-zip-code'),
                              label: 'Posta kodu',
                              controller: _buyerZipCodeController,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Fatura adresi',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            _checkoutField(
                              key: const ValueKey(
                                'driver-plan-billing-address',
                              ),
                              label: 'Adres',
                              controller: _billingAddressController,
                            ),
                            _checkoutField(
                              key: const ValueKey(
                                'driver-plan-billing-contact-name',
                              ),
                              label: '\u0130leti\u015fim ad\u0131',
                              controller: _billingContactNameController,
                            ),
                            _checkoutField(
                              key: const ValueKey('driver-plan-billing-city'),
                              label: '\u015eehir',
                              controller: _billingCityController,
                            ),
                            _checkoutField(
                              key: const ValueKey(
                                'driver-plan-billing-country',
                              ),
                              label: '\u00dclke',
                              controller: _billingCountryController,
                            ),
                            _checkoutField(
                              key: const ValueKey(
                                'driver-plan-billing-zip-code',
                              ),
                              label: 'Posta kodu',
                              controller: _billingZipCodeController,
                            ),
                          ],
                        ),
                      ),
                      if (controller.checkoutErrorMessage case final error?) ...[
                        const SizedBox(height: 4),
                        Text(
                          error,
                          key: const ValueKey(
                            'driver-plan-checkout-error',
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        key: const ValueKey(
                          'driver-plan-checkout-initialize',
                        ),
                        onPressed: controller.checkoutInitializing
                            ? null
                            : _initializeCheckout,
                        child: controller.checkoutInitializing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                '\u00d6deme Sayfas\u0131n\u0131 Haz\u0131rla',
                              ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('driver-plan-purchase-prepare'),
                    onPressed:
                        controller.preparing ||
                            prepared != null ||
                            controller.selectedPlan == null ||
                            !controller.isPlanEnabled(controller.selectedPlan!)
                        ? null
                        : controller.prepare,
                    child: controller.preparing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            prepared != null
                                ? 'Talep Hazırlandı'
                                : controller.errorMessage != null
                                ? 'Tekrar Dene'
                                : 'Talebi Hazırla',
                          ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
