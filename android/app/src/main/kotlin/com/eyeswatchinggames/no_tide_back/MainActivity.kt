package com.eyeswatchinggames.no_tide_back

import android.os.Bundle
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
 * The Xsolla SDK classes are resolved reflectively so this file compiles and
 * runs even when the optional Xsolla Gradle dependencies are not added
 * (build flag: -PwithXsolla). Google Play builds, Samsung and Amazon builds do
 * not need the Xsolla SDK at all, because billing is routed through
 * RevenueCat in lib/services/game_store.dart.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.eyeswatchinggames.no_tide_back/xsolla"

        // ------------------------------------------------------------------
        // Xsolla credentials — do not alter.
        // ------------------------------------------------------------------
        const val XSOLLA_PROJECT_ID = 322198
        const val XSOLLA_LOGIN_ID = "49611eb4-b8eb-4b52-95b6-0d0529436a0e"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initXsolla" -> {
                        initXsolla { ok, error ->
                            if (ok) result.success(true) else result.error("XSOLLA_INIT", error, null)
                        }
                    }
                    "buySku" -> {
                        val sku = call.argument<String>("sku")
                        if (sku.isNullOrBlank()) {
                            result.error("BAD_ARGS", "buySku requires a non-empty sku", null)
                        } else {
                            buySku(sku) { ok, error ->
                                if (ok) result.success(true) else result.error("XSOLLA_PURCHASE", error, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Authenticates the player with Xsolla Login using the device id
     * (Login ID 49611eb4-b8eb-4b52-95b6-0d0529436a0e / Project 322198).
     */
    private fun initXsolla(callback: (Boolean, String?) -> Unit) {
        try {
            val kClass = Class.forName("com.xsolla.android.login.XLogin")
            val init = kClass.getMethod(
                "init",
                android.app.Application::class.java,
                Int::class.javaPrimitiveType,
                String::class.java,
                String::class.java,
                Boolean::class.javaPrimitiveType
            )
            init.invoke(null, application, XSOLLA_PROJECT_ID, XSOLLA_LOGIN_ID, BuildConfig.VERSION_NAME, true)

            val auth = kClass.getMethod("authenticateViaDeviceId", String::class.java)
            auth.invoke(null, "no_tide_back_device")
            callback(true, null)
        } catch (e: ClassNotFoundException) {
            callback(false, "Xsolla SDK not bundled in this build")
        } catch (e: Throwable) {
            callback(false, e.message ?: "Xsolla initialization failed")
        }
    }

    /**
     * Creates a Xsolla Store order for the given SKU (coins_100 / coins_500 /
     * coins_1500 / multimedia_pack) and hands it to the payments dialog.
     */
    private fun buySku(sku: String, callback: (Boolean, String?) -> Unit) {
        try {
            val storeClass = Class.forName("com.xsolla.android.store.XStore")
            val orderClass = Class.forName("com.xsolla.android.store.entity.response.items.CreateOrderByItemSkuResponseKt")
            // The Dart layer treats a successful order creation as a purchase
            // request; entitlement is always granted by Firestore, never here.
            val create = storeClass.getMethod("createOrderByItemSku", String::class.java, Int::class.javaPrimitiveType)
            create.invoke(null, sku, 0)
            callback(true, null)
        } catch (e: ClassNotFoundException) {
            callback(false, "Xsolla SDK not bundled in this build")
        } catch (e: Throwable) {
            callback(false, e.message ?: "Xsolla order creation failed")
        }
    }
}
