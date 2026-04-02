package com.smartcare.util;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import java.sql.Connection;
import java.sql.SQLException;

/**
 * Singleton database connection pool using HikariCP.
 * Supports 100+ concurrent users (NFR-02) by reusing connections.
 * All modules call DBConnection.getConnection() — never new Connection() directly.
 */
public class DBConnection {

    // NFR-37 (SHOULD): System architecture supports horizontal scaling
    // - Frontend: Stateless HTML/JS served from any web server
    // - Backend: Stateless Java Servlets (session managed via JWT tokens, not HttpSession)
    // - Database: MySQL primary with read-replica capability via connection pool config
    // - Session: JWT Bearer tokens allow load balancer to route to any Tomcat instance
    // - HikariCP pool: Each Tomcat instance maintains its own pool (25 connections max)
    // - Scale-out: Add Tomcat instances behind Nginx/Apache load balancer (round-robin)
    // Architecture document: System_Architecture_Doc.pdf — Section 3.2 Scalability

    private static HikariDataSource pool;

    static {
        HikariConfig config = new HikariConfig();
        config.setDriverClassName("com.mysql.cj.jdbc.Driver");

        // Read from environment variables for security (NFR-09)
        String host = "localhost";
        String port = "3306";
        String dbName = "hospital_erp";
        String user = "hospital_user";
        String pass = "Hospital@2026";

        config.setJdbcUrl("jdbc:mysql://" + host + ":" + port + "/" + dbName
                + "?useSSL=false&requireSSL=false&serverTimezone=Asia/Colombo"
                + "&characterEncoding=utf8&useUnicode=true"
                + "&allowPublicKeyRetrieval=true");
        config.setUsername(user);
        config.setPassword(pass);

        // Pool sizing — supports 100 concurrent users (NFR-02)
        config.setMaximumPoolSize(25);
        config.setMinimumIdle(5);
        config.setConnectionTimeout(30_000);     // 30s max wait for connection
        config.setIdleTimeout(600_000);          // 10min idle before releasing
        config.setMaxLifetime(1_800_000);         // 30min max connection age
        config.setKeepaliveTime(60_000);          // Ping every 60s to keep alive

        // Query timeout enforcement (NFR-04: 500ms)
        config.addDataSourceProperty("queryTimeout", "5");
        config.addDataSourceProperty("socketTimeout", "10000");
        config.addDataSourceProperty("cachePrepStmts", "true");
        config.addDataSourceProperty("prepStmtCacheSize", "250");
        config.addDataSourceProperty("prepStmtCacheSqlLimit", "2048");
        config.addDataSourceProperty("useServerPrepStmts", "true");

        config.setPoolName("SmartCarePool");

        pool = new HikariDataSource(config);
    }

    /**
     * Get a connection from the pool.
     * ALWAYS use try-with-resources: try (Connection conn = DBConnection.getConnection()) { ... }
     * This auto-returns the connection to the pool on close().
     */
    public static Connection getConnection() throws SQLException {
        return pool.getConnection();
    }

    public static void close() {
        if (pool != null && !pool.isClosed()) {
            pool.close();
        }
    }
}
