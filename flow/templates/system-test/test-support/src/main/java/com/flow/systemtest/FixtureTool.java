package com.flow.systemtest;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;

/**
 * Executes a SQL fixture file against MySQL.
 * Usage: FixtureTool &lt;sql-file&gt; [database]
 */
public final class FixtureTool {
    private FixtureTool() {}

    public static void main(String[] args) throws Exception {
        if (args.length < 1 || args.length > 2) {
            throw new IllegalArgumentException("Usage: FixtureTool <sql-file> [database]");
        }
        Path sqlPath = Paths.get(args[0]);
        if (!Files.exists(sqlPath)) {
            throw new IllegalArgumentException("SQL fixture not found: " + sqlPath.toAbsolutePath());
        }
        String database = args.length == 2 && args[1] != null && !args[1].trim().isEmpty()
                ? args[1].trim()
                : Environment.required("MYSQL_DATABASE");
        String jdbc = "jdbc:mysql://" + Environment.value("MYSQL_HOST", "127.0.0.1") + ":"
                + Environment.value("MYSQL_PORT", "3306") + "/" + database
                + "?useUnicode=true&characterEncoding=utf8&useSSL=false&allowPublicKeyRetrieval=true"
                + "&allowMultiQueries=true";
        String sql = new String(Files.readAllBytes(sqlPath), StandardCharsets.UTF_8)
                .replaceAll("(?m)^\\s*--.*$", "");
        System.out.println("FixtureTool database=" + database + " file=" + sqlPath.toAbsolutePath());
        try (Connection connection = DriverManager.getConnection(jdbc,
                Environment.value("MYSQL_USER", "root"), Environment.value("MYSQL_PASSWORD", ""));
             Statement statement = connection.createStatement()) {
            for (String command : sql.split(";")) {
                if (!command.trim().isEmpty()) {
                    statement.execute(command.trim());
                }
            }
        }
        System.out.println("FixtureTool OK");
    }
}
