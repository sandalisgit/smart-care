package com.smartcare.util;

import com.google.gson.*;
import java.lang.reflect.Type;
import java.time.*;
import java.time.format.DateTimeFormatter;

/**
 * Centralized JSON utility using Gson.
 * Handles Java 8 date/time types correctly.
 */
public class JsonUtil {

    private static final Gson GSON = new GsonBuilder()
            .setPrettyPrinting()
            .serializeNulls()
            // Handle java.sql.Date / java.util.Date
            .setDateFormat("yyyy-MM-dd'T'HH:mm:ss")
            .create();

    public static String toJson(Object obj) {
        return GSON.toJson(obj);
    }

    public static <T> T fromJson(String json, Class<T> clazz) {
        return GSON.fromJson(json, clazz);
    }

    public static <T> T fromJson(String json, Type type) {
        return GSON.fromJson(json, type);
    }

    /** Standard success response wrapper */
    public static String success(Object data) {
        JsonObject resp = new JsonObject();
        resp.addProperty("success", true);
        resp.add("data", GSON.toJsonTree(data));
        return GSON.toJson(resp);
    }

    /** Standard success with message */
    public static String success(String message, Object data) {
        JsonObject resp = new JsonObject();
        resp.addProperty("success", true);
        resp.addProperty("message", message);
        resp.add("data", GSON.toJsonTree(data));
        return GSON.toJson(resp);
    }

    /** Standard error response wrapper */
    public static String error(String message) {
        JsonObject resp = new JsonObject();
        resp.addProperty("success", false);
        resp.addProperty("error", message);
        return GSON.toJson(resp);
    }

    /** Error with HTTP status guidance */
    public static String error(String message, String code) {
        JsonObject resp = new JsonObject();
        resp.addProperty("success", false);
        resp.addProperty("error", message);
        resp.addProperty("code", code);
        return GSON.toJson(resp);
    }
}
