//  Label StoreMax
//
//  Created by Anthony Gordon.
//  2023, WooSignal Ltd. All rights reserved.
//

//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/cart_line_item.dart';
import 'package:flutter_app/app/models/checkout_session.dart';
import 'package:flutter_app/app/models/customer_address.dart';
import 'package:flutter_app/bootstrap/app_helper.dart';
import 'package:flutter_app/bootstrap/helpers.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'dart:async';
import 'package:webview_flutter/webview_flutter.dart';
// #docregion platform_imports
// Import for Android features.
import 'package:webview_flutter_android/webview_flutter_android.dart';
// Import for iOS features.
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
// #enddocregion platform_imports
import 'package:woosignal/models/response/woosignal_app.dart';

class PayPalCheckout extends StatefulWidget {
  final String? description;
  final String? amount;
  final List<CartLineItem>? cartLineItems;

  PayPalCheckout({this.description, this.amount, this.cartLineItems});

  @override
  WebViewState createState() => WebViewState();
}

class WebViewState extends NyState<PayPalCheckout> {
  late final WebViewController _controller;
  /*
      late Completer<WebViewController> _controller =
      Completer<WebViewController>();
  */

  String? payerId = '';
  int intCount = 0;
  StreamSubscription<String>? _onUrlChanged;
  final WooSignalApp? _wooSignalApp = AppHelper.instance.appConfig;
  String? formCheckoutShippingAddress;

  setCheckoutShippingAddress(CustomerAddress customerAddress) {
    String tmp = "";
    if (customerAddress.firstName != null) {
      tmp +=
          '<input type="hidden" name="first_name" value="${customerAddress.firstName!.replaceAll(RegExp(r'[^\d\w\s,\-+]+'), '')}">\n';
    }
    if (customerAddress.lastName != null) {
      tmp +=
          '<input type="hidden" name="last_name" value="${customerAddress.lastName!.replaceAll(RegExp(r'[^\d\w\s,\-+]+'), '')}">\n';
    }
    if (customerAddress.addressLine != null) {
      tmp +=
          '<input type="hidden" name="address1" value="${customerAddress.addressLine!.replaceAll(RegExp(r'[^\d\w\s,\-+]+'), '')}">\n';
    }
    if (customerAddress.city != null) {
      tmp +=
          '<input type="hidden" name="city" value="${customerAddress.city!.replaceAll(RegExp(r'[^\d\w\s,\-+]+'), '')}">\n';
    }
    if (customerAddress.customerCountry!.hasState() &&
        customerAddress.customerCountry!.state!.name != null) {
      tmp +=
          '<input type="hidden" name="state" value="${customerAddress.customerCountry!.state!.name!.replaceAll(RegExp(r'[^\d\w\s,\-+]+'), '')}">\n';
    }
    if (customerAddress.postalCode != null) {
      tmp +=
          '<input type="hidden" name="zip" value="${customerAddress.postalCode!.replaceAll(RegExp(r'[^\d\w\s,\-+]+'), '')}">\n';
    }
    if (customerAddress.customerCountry!.countryCode != null) {
      tmp +=
          '<input type="hidden" name="country" value="${customerAddress.customerCountry!.countryCode!.replaceAll(RegExp(r'[^\d\w\s,\-+]+'), '')}">\n';
    }
    formCheckoutShippingAddress = tmp;
  }

  String getPayPalItemName() {
    return truncateString(
        widget.description!.replaceAll(RegExp(r'[^\w\s]+'), ''), 124);
  }

  String getPayPalPaymentType() {
    return Platform.isAndroid ? "PayPal - Android App" : "PayPal - IOS App";
  }

  String getPayPalUrl() {
    bool? liveMode =
        envVal('PAYPAL_LIVE_MODE', defaultValue: _wooSignalApp!.paypalLiveMode);
    return liveMode == true
        ? "https://www.paypal.com/cgi-bin/webscr"
        : "https://www.sandbox.paypal.com/cgi-bin/webscr";
  }

  @override
  void initState() {
    super.initState();

    // #docregion platform_features
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
    WebViewController.fromPlatformCreationParams(params);
    // #enddocregion platform_features

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebView is loading (progress : $progress%)');
          },
          onPageStarted: (String url) {
            debugPrint('Page started loading: $url');
          },
          onPageFinished: (String url) {
            debugPrint('Page finished loading: $url');
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
Page resource error:
  code: ${error.errorCode}
  description: ${error.description}
  errorType: ${error.errorType}
  isForMainFrame: ${error.isForMainFrame}
          ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('https://www.youtube.com/')) {
              debugPrint('blocking navigation to ${request.url}');
              return NavigationDecision.prevent;
            }
            debugPrint('allowing navigation to ${request.url}');
            return NavigationDecision.navigate;
          },
          onUrlChange: (UrlChange change) {
            debugPrint('url change to ${change.url}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'Toaster',
        onMessageReceived: (JavaScriptMessage message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message.message)),
          );
        },
      )
      ..loadRequest(Uri.parse('https://flutter.dev'));

    // #docregion platform_features
    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    // #enddocregion platform_features

    _controller = controller;

   // if (Platform.isAndroid) WebView.platform = SurfaceAndroidWebView();
    setCheckoutShippingAddress(
        CheckoutSession.getInstance.billingDetails!.shippingAddress!);
    setState(() {});
  }

  @override
  void dispose() {
    if (_onUrlChanged != null) {
      _onUrlChanged!.cancel();
    }
    super.dispose();
  }

  String _loadHTML() {
    final String strProcessingPayment = trans("Processing Payment");
    final String strPleaseWait = trans(
        "Please wait, your order is being processed and you will be redirected to the PayPal website.");
    final String strRedirectMessage = trans(
        "If you are not automatically redirected to PayPal within 5 seconds");

    return '''
      <html><head><title>$strProcessingPayment...</title></head>
<body onload="document.forms['paypal_form'].submit();">
<div style="text-align:center;">
<img src="https://woosignal.com/images/paypal_logo.png" height="50" />
</div>
<center><h4>$strPleaseWait</h4></center>
<form method="post" name="paypal_form" action="${getPayPalUrl()}">
<input type="hidden" name="cmd" value="_xclick">
<input type="hidden" name="amount" value="${widget.amount}">
<input type="hidden" name="lc" value="${envVal('PAYPAL_LOCALE', defaultValue: _wooSignalApp!.paypalLocale)}">
<input type="hidden" name="currency_code" value="${_wooSignalApp!.currencyMeta!.code}">
<input type="hidden" name="business" value="${envVal('PAYPAL_ACCOUNT_EMAIL', defaultValue: _wooSignalApp!.paypalEmail)}">
<input type="hidden" name="return" value="https://woosignal.com/paypal/payment~success">
<input type="hidden" name="cancel_return" value="https://woosignal.com/paypal/payment~failure">
<input type="hidden" name="item_name" value="${getPayPalItemName()}">
<input type="hidden" name="custom" value="${getPayPalPaymentType()}">
<input type="hidden" name="address_override" value="1">
$formCheckoutShippingAddress
<center><br><br>$strRedirectMessage...<br><br>
<input type="submit" value="Click Here"></center>
</form></body></html>
'''
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: WebViewWidget(
          /*
          initialUrl:
              Uri.dataFromString(_loadHTML(), mimeType: 'text/html').toString(),
          javascriptMode: JavascriptMode.unrestricted,
          onWebViewCreated: (WebViewController webViewController) {
            _controller.complete(webViewController);
          },
          onProgress: (int progress) {},
          navigationDelegate: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {
            if (intCount > 0) {
              url = url.replaceAll("~", "_");
            }

            intCount = intCount + 1;
            if (url.contains("payment_success")) {
              var uri = Uri.dataFromString(url);
              setState(() {
                payerId = uri.queryParameters['PayerID'];
              });
              Navigator.pop(context, {
                "status": payerId == null ? "cancelled" : "success",
                "payerId": payerId
              });
            } else if (url.contains("payment_failure")) {
              Navigator.pop(context, {"status": "cancelled"});
            }
          },
          gestureNavigationEnabled: false,
          */
          controller: _controller,
        ),
      ),
    );
  }
}
