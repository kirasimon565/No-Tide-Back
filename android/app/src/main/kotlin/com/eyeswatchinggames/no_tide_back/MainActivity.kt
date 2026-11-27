package com.eyeswatchinggames.no_tide_back

import android.app.Activity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity for No Tide Back.
 *
 * Package, MethodChannel name and Xsolla credentials must never change:
 *   package      : com.eyeswatchinggames.no_tide_back
 *   channel      : com.eyeswatchinggames.no_tide_back/xsolla
 *   Xsolla login : 49611eb4-b8eb-4b52-95b6-0d0529436a0e
 *   Xsolla proj  : 322198
 *
 * ---------------------------------------------------------------------------
 * Which Xsolla SDK this targets
 * ---------------------------------------------------------------------------
 * Xsolla retired the old `login` / `payments` / `store` 3.1.0 artifacts (the
 * Gradle error "Could not find com.xsolla.android:store:3.1.0" is that
 * retirement, not a repo misconfiguration). The current SDK is a single
 * artifact that mirrors the Google Play Billing API:
 *
 *   com.xsolla.android:mobile:<version>
 *   maven { url "https://raw.githubusercontent.com/xsolla/xsolla-sdk-android/main" }
 *
 * It talks to Xsolla Pay Station, which also fronts Google Play purchases, so
 * this one rail covers the store without a second billing integration.
 *
 * The SDK is an *optional* dependency (build flag `-PwithXsolla`). Play /
 * Amazon / Samsung builds do not bundle it, so every call below is reflective:
 * this file compiles and runs against a classpath that does not contain it.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.eyeswatchinggames.no_tide_back/xsolla"

        /// Matches StoreChannel._channel in lib/services/store_channel.dart.
        const val STORE_CHANNEL = "com.eyeswatchinggames.no_tide_back/store"

        // ------------------------------------------------------------------
        // Xsolla credentials — do not alter.
        // ------------------------------------------------------------------
        const val XSOLLA_PROJECT_ID = 322198
        const val XSOLLA_LOGIN_ID = "49611eb4-b8eb-4b52-95b6-0d0529436a0e"

        const val SDK_PACKAGE = "com.xsolla.android.mobile"
        const val DESCRIPTOR = "com.xsolla.android.mobile."

        /// Shown verbatim by the store sheet when the AAR is not on the
        /// classpath (Play / Amazon / Samsung builds). Never a silent failure.
        const val NOT_BUNDLED =
            "This build has no Xsolla SDK bundled. Rebuild with -PwithXsolla " +
                "(the release workflows do this for the xsolla flavor)."
    }

    private var pendingSku: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var billingClient: Any? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initXsolla" -> connect { ok, error ->
                        if (ok) result.success(true) else result.error("XSOLLA_INIT", error, null)
                    }
                    "buySku" -> {
                        val sku = call.argument<String>("sku")
                        if (sku.isNullOrBlank()) {
                            result.error("BAD_ARGS", "buySku requires a non-empty sku", null)
                        } else {
                            purchase(sku, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Install source: which store this APK came from. RevenueCat needs the
        // matching project key, and the compiled rail cannot know whether the
        // user installed from Play, Galaxy, or Amazon.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installerPackage" -> result.success(installerPackage())
                    else -> result.notImplemented()
                }
            }
    }

    /// `com.android.vending`, `com.amazon.venezia`, `com.sec.android.app.samsungapps`,
    /// or null for a sideload (a null name here is normal, not an error).
    private fun installerPackage(): String? = try {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName)
        }
    } catch (e: Exception) {
        android.util.Log.w("StoreChannel", "installerPackage unavailable", e)
        null
    }

    // ------------------------------------------------------------------------
    // Bridge helpers
    // ------------------------------------------------------------------------
    private fun sdkClass(simpleName: String): Class<*> = Class.forName(DESCRIPTOR + simpleName)

    /// `ProjectId.parse()` / `LoginUuid.parse()` return an Either; unwrap the
    /// right side (a malformed credential throws, which surfaces as XSOLLA_INIT).
    private fun unwrap(either: Any?): Any {
        requireNotNull(either) { "Xsolla SDK returned no value for a credential" }
        return either.javaClass.getMethod("getRightOrThrow").invoke(either)
    }

    private fun isSdkBundled(): Boolean = try {
        Class.forName(DESCRIPTOR + "BillingClient")
        true
    } catch (_: ClassNotFoundException) {
        false
    }

    /**
     * Creates the BillingClient with auto-JWT authentication for
     * Project 322198 / Login 49611eb4-…, then starts the connection.
     *
     * Mirrors the SDK's documented Kotlin usage:
     *   Config(Config.Common.getDefault(), Config.Integration.forXsolla(
     *     Config.Integration.Xsolla.Authentication.forAutoJWT(projectId, loginId)),
     *     Config.Payments.getDefault(), Config.Analytics.getDefault())
     */
    private fun connect(callback: (Boolean, String?) -> Unit) {
        if (!isSdkBundled()) {
            callback(false, NOT_BUNDLED)
            return
        }
        try {
            val commonClass = sdkClass("ConfigWithoutIntegration\$Common")
            val paymentsClass = sdkClass("ConfigWithoutIntegration\$Payments")
            val analyticsClass = sdkClass("ConfigWithoutIntegration\$Analytics")
            val integrationClass = sdkClass("Config\$Integration")
            val authClass = sdkClass("Config\$Integration\$Xsolla\$Authentication")
            val configClass = sdkClass("Config")
            val projectIdClass = sdkClass("ProjectId")
            val loginUuidClass = sdkClass("LoginUuid")
            val billingClientClass = sdkClass("BillingClient")
            val stateListenerClass = sdkClass("BillingClientStateListener")
            val updatedListenerClass = sdkClass("PurchasesUpdatedListener")

            val common = commonClass.getMethod("getDefault").invoke(null)
            val payments = paymentsClass.getMethod("getDefault").invoke(null)
            val analytics = analyticsClass.getMethod("getDefault").invoke(null)

            // ProjectId.parse(int) / LoginUuid.parse(String) return Either;
            // getRightOrThrow() unwraps them (an invalid credential throws here,
            // which surfaces to Dart as XSOLLA_INIT instead of a silent hang).
            val projectId = unwrap(
                projectIdClass.getMethod("parse", Int::class.javaPrimitiveType)
                    .invoke(null, XSOLLA_PROJECT_ID),
            )
            val loginUuid = unwrap(
                loginUuidClass.getMethod("parse", String::class.java)
                    .invoke(null, XSOLLA_LOGIN_ID),
            )

            val auth = authClass
                .getMethod("forAutoJWT", projectIdClass, loginUuidClass)
                .invoke(null, projectId, loginUuid)
            val integration = integrationClass
                .getMethod("forXsolla", authClass)
                .invoke(null, auth)

            val config = configClass
                .getConstructor(commonClass, integrationClass, paymentsClass, analyticsClass)
                .newInstance(common, integration, payments, analytics)

            val updatesListener = java.lang.reflect.Proxy.newProxyInstance(
                classLoader,
                arrayOf(updatedListenerClass),
            ) { _, method, args ->
                if (method.name == "onPurchasesUpdated") handlePurchasesUpdated(args)
                null
            }

            val builder = billingClientClass.getMethod("newBuilder", android.content.Context::class.java)
                .invoke(null, applicationContext)
            builder.javaClass.getMethod("setListener", updatedListenerClass)
                .invoke(builder, updatesListener)
            builder.javaClass.getMethod("setConfig", configClass).invoke(builder, config)
            val client = builder.javaClass.getMethod("build").invoke(builder)
            billingClient = client

            val stateListener = java.lang.reflect.Proxy.newProxyInstance(
                classLoader,
                arrayOf(stateListenerClass),
            ) { _, method, args ->
                if (method.name == "onBillingSetupFinished") {
                    // `startConnection` reports its own failure here; treating
                    // every callback as success used to hide a bad project id or
                    // missing network behind a confusing "no product" error.
                    val result = args?.getOrNull(0)
                    val code = result?.javaClass?.getMethod("getResponseCode")
                        ?.invoke(result) as? Int ?: -1
                    if (code == 0) {
                        callback(true, null)
                    } else {
                        val detail = result?.javaClass?.getMethod("getDebugMessage")
                            ?.invoke(result) as? String
                        callback(
                            false,
                            detail ?: "Xsolla could not connect (code $code). " +
                                "Check the project id, the login id and the network.",
                        )
                    }
                }
                null
            }
            billingClientClass.getMethod("startConnection", stateListenerClass)
                .invoke(client, stateListener)
        } catch (e: ClassNotFoundException) {
            callback(false, NOT_BUNDLED)
        } catch (e: Throwable) {
            // Reflection against a moved SDK throws NoSuchMethod/IllegalAccess;
            // name the class so a version bump is obvious in logcat.
            android.util.Log.e("XsollaBridge", "connect failed", e)
            callback(
                false,
                e.cause?.message ?: e.message
                    ?: "${e.javaClass.simpleName} while starting the Xsolla client",
            )
        }
    }

    /**
     * Two-step purchase: resolve the ProductDetails for the SKU, then launch the
     * Pay Station flow. Entitlement is granted by Firestore only after the
     * purchase listener fires, never here.
     */
    private fun purchase(sku: String, result: MethodChannel.Result) {
        val client = billingClient
        if (client == null) {
            connect { ok, error ->
                if (!ok) {
                    result.error("XSOLLA_INIT", error, null)
                } else {
                    purchase(sku, result)
                }
            }
            return
        }
        if (pendingResult != null) {
            result.error("XSOLLA_BUSY", "A purchase is already in progress", null)
            return
        }
        pendingSku = sku
        pendingResult = result
        try {
            val productClass = sdkClass("QueryProductDetailsParams\$Product")
            val paramsClass = sdkClass("QueryProductDetailsParams")
            val listenerClass = sdkClass("ProductDetailsResponseListener")
            val billingClientClass = sdkClass("BillingClient")

            val productType = billingClientClass.getField("ProductType").get(null)
            val inApp = productType.javaClass.getField("INAPP").get(productType)

            val productBuilder = productClass.getMethod("newBuilder").invoke(null)
            productClass.getMethod("setProductId", String::class.java)
                .invoke(productBuilder, sku)
            productClass.getMethod("setProductType", String::class.java)
                .invoke(productBuilder, inApp)
            val product = productClass.getMethod("build").invoke(productBuilder)

            val paramsBuilder = paramsClass.getMethod("newBuilder").invoke(null)
            paramsClass.getMethod("setProductList", List::class.java)
                .invoke(paramsBuilder, listOf(product))
            val params = paramsClass.getMethod("build").invoke(paramsBuilder)

            val listener = java.lang.reflect.Proxy.newProxyInstance(
                classLoader,
                arrayOf(listenerClass),
            ) { _, method, args ->
                if (method.name == "onProductDetailsResponse" && args != null && args.size == 2) {
                    @Suppress("UNCHECKED_CAST")
                    val products = args[1] as? List<Any?>
                    val first = products?.firstOrNull()
                    if (first == null) {
                        // Pay Station answers OK with an empty list when the SKU
                        // is not in the project's catalog. Say exactly that,
                        // because it is a dashboard fix, not an app bug.
                        failPending(
                            "SKU_UNAVAILABLE",
                            "No product \"$sku\" in the Xsolla catalog for project " +
                                "$XSOLLA_PROJECT_ID. Add the SKU (coin packs and the " +
                                "multimedia pack) in Xsolla Publisher Account → Store.",
                        )
                    } else {
                        launchFlow(first)
                    }
                }
                null
            }

            // Watchdog: a dead network used to leave the Dart side awaiting a
            // result forever, which disabled every BUY button in the sheet.
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(
                {
                    if (pendingSku == sku) {
                        failPending(
                            "XSOLLA_TIMEOUT",
                            "Pay Station did not answer within 25 s. Check the connection and retry.",
                        )
                    }
                },
                25_000,
            )

            billingClientClass
                .getMethod("queryProductDetailsAsync", paramsClass, listenerClass)
                .invoke(client, params, listener)
        } catch (e: Throwable) {
            android.util.Log.e("XsollaBridge", "queryProductDetails failed", e)
            failPending("XSOLLA_QUERY", e.message ?: "Product query failed")
        }
    }

    private fun launchFlow(productDetails: Any) {
        val client = billingClient ?: run {
            failPending("XSOLLA_INIT", "Billing client is gone")
            return
        }
        try {
            val detailsParamsClass = sdkClass("BillingFlowParams\$ProductDetailsParams")
            val flowParamsClass = sdkClass("BillingFlowParams")
            val billingClientClass = sdkClass("BillingClient")

            val detailsBuilder = detailsParamsClass.getMethod("newBuilder").invoke(null)
            detailsParamsClass.getMethod(
                "setProductDetails",
                sdkClass("ProductDetails"),
            ).invoke(detailsBuilder, productDetails)
            val detailsParams = detailsParamsClass.getMethod("build").invoke(detailsBuilder)

            val flowBuilder = flowParamsClass.getMethod("newBuilder").invoke(null)
            flowParamsClass.getMethod("setProductDetailsParamsList", List::class.java)
                .invoke(flowBuilder, listOf(detailsParams))
            val flowParams = flowParamsClass.getMethod("build").invoke(flowBuilder)

            // launchBillingFlow returns a BillingResult; a non-OK code means the
            // sheet never opened (the listener will not fire in that case).
            val billingResult = billingClientClass
                .getMethod("launchBillingFlow", Activity::class.java, flowParamsClass)
                .invoke(client, this, flowParams)
            val code = billingResult.javaClass.getMethod("getResponseCode").invoke(billingResult) as Int
            if (code != 0) { // BillingResponseCode.OK
                val message = billingResult.javaClass.getMethod("getDebugMessage")
                    .invoke(billingResult) as? String
                failPending("XSOLLA_FLOW", message ?: "Billing flow refused (code $code)")
            }
        } catch (e: Throwable) {
            failPending("XSOLLA_FLOW", e.message ?: "Could not open the Pay Station sheet")
        }
    }

    /** PurchasesUpdatedListener → Dart. Success is reported per purchase. */
    private fun handlePurchasesUpdated(args: Array<out Any?>?) {
        val billingResult = args?.getOrNull(0) ?: return
        val purchases = args.getOrNull(1) as? List<*>
        val code = billingResult.javaClass.getMethod("getResponseCode").invoke(billingResult) as Int

        if (code != 0 || purchases.isNullOrEmpty()) { // not OK / nothing bought
            val message = billingResult.javaClass.getMethod("getDebugMessage")
                .invoke(billingResult) as? String
            failPending(
                if (code == 1) "XSOLLA_CANCELLED" else "XSOLLA_PURCHASE",
                message ?: "Purchase not completed (code $code)",
            )
            return
        }

        val purchase = purchases.firstOrNull()
        if (purchase == null) {
            failPending("XSOLLA_PURCHASE", "Purchase list was empty")
            return
        }
        val token = purchase.javaClass.getMethod("getPurchaseToken").invoke(purchase) as? String
        failOrSucceed(token)
    }

    private fun failOrSucceed(purchaseToken: String?) {
        val result = pendingResult
        val sku = pendingSku
        pendingResult = null
        pendingSku = null
        if (result == null) return
        if (purchaseToken.isNullOrBlank()) {
            result.error("XSOLLA_PURCHASE", "Purchase returned without a token", null)
        } else {
            // Firestore (lib/services/game_store.dart) verifies and records the
            // entitlement; this layer never grants coins itself.
            result.success(
                mapOf(
                    "sku" to sku,
                    "purchaseToken" to purchaseToken,
                ),
            )
        }
    }

    private fun failPending(code: String, message: String) {
        val result = pendingResult
        pendingResult = null
        pendingSku = null
        result?.error(code, message, null)
    }

}
