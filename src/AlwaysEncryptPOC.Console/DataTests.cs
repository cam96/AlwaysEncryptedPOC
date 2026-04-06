using System.Data;
using Microsoft.Data.SqlClient;

namespace AlwaysEncryptPOC.Console;

public class DataTests
{
    private readonly string _plainConnectionString;
    private readonly string _aeConnectionString;
    private readonly string _enclaveConnectionString;

    // Maps table names to their corresponding stored procedure names
    private static readonly Dictionary<string, string> InsertSpMap = new()
    {
        ["dbo.PlainData"] = "dbo.usp_InsertPlainData",
        ["dbo.EncryptedNoEnclave"] = "dbo.usp_InsertEncryptedNoEnclave",
        ["dbo.EncryptedWithEnclave"] = "dbo.usp_InsertEncryptedWithEnclave",
    };

    private static readonly Dictionary<string, string> GetAllSpMap = new()
    {
        ["dbo.PlainData"] = "dbo.usp_GetAllPlainData",
        ["dbo.EncryptedNoEnclave"] = "dbo.usp_GetAllEncryptedNoEnclave",
        ["dbo.EncryptedWithEnclave"] = "dbo.usp_GetAllEncryptedWithEnclave",
        ["dbo.EncryptedNoEnclave_Target"] = "dbo.usp_GetAllEncryptedNoEnclaveTarget",
        ["dbo.EncryptedWithEnclave_Target"] = "dbo.usp_GetAllEncryptedWithEnclaveTarget",
    };

    private static readonly Dictionary<string, string> UpdateSalarySpMap = new()
    {
        ["dbo.EncryptedNoEnclave"] = "dbo.usp_UpdateSalaryEncryptedNoEnclave",
        ["dbo.EncryptedWithEnclave"] = "dbo.usp_UpdateSalaryEncryptedWithEnclave",
    };

    private static readonly Dictionary<string, string> QueryBySsnSpMap = new()
    {
        ["dbo.EncryptedNoEnclave"] = "dbo.usp_QueryBySsnEncryptedNoEnclave",
        ["dbo.EncryptedWithEnclave"] = "dbo.usp_QueryBySsnEncryptedWithEnclave",
    };

    private static readonly Dictionary<string, string> QueryByFullNameSpMap = new()
    {
        ["dbo.EncryptedNoEnclave"] = "dbo.usp_QueryByFullNameEncryptedNoEnclave",
        ["dbo.EncryptedWithEnclave"] = "dbo.usp_QueryByFullNameEncryptedWithEnclave",
    };

    public DataTests(string plainConnectionString, string aeConnectionString, string enclaveConnectionString)
    {
        _plainConnectionString = plainConnectionString;
        _aeConnectionString = aeConnectionString;
        _enclaveConnectionString = enclaveConnectionString;
    }

    // ========================================================================
    // Data Seeding
    // ========================================================================

    public async Task SeedDataAsync()
    {
        System.Console.WriteLine("=== Seeding Data ===\n");

        var rows = new[]
        {
            (SSN: "795-73-9838", FullName: "Catherine Abel",     Salary: 31692.00m),
            (SSN: "990-00-6818", FullName: "Kim Abercrombie",    Salary: 55415.00m),
            (SSN: "123-45-6789", FullName: "John Smith",         Salary: 72000.00m),
            (SSN: "987-65-4321", FullName: "Maria Garcia",       Salary: 89500.00m),
            (SSN: "555-12-3456", FullName: "Robert Johnson",     Salary: 45000.00m),
        };

        System.Console.WriteLine("  Seed data (5 rows, identical across all 3 tables):");
        for (int i = 0; i < rows.Length; i++)
        {
            System.Console.WriteLine($"    Row {i + 1}: SSN={rows[i].SSN}, FullName={rows[i].FullName}, Salary={rows[i].Salary:C}");
        }
        System.Console.WriteLine();

        // Seed PlainData — no encryption needed
        await using (var plainConn = await OpenConnectionAsync(_plainConnectionString))
        {
            foreach (var row in rows)
                await InsertRowAsync(plainConn, "dbo.PlainData", row.SSN, row.FullName, row.Salary);
        }
        System.Console.WriteLine("  Seeded PlainData (5 rows)");

        // Seed EncryptedNoEnclave — driver auto-encrypts via Column Encryption Setting
        await using (var aeConn = await OpenConnectionAsync(_aeConnectionString))
        {
            foreach (var row in rows)
                await InsertRowAsync(aeConn, "dbo.EncryptedNoEnclave", row.SSN, row.FullName, row.Salary);
        }
        System.Console.WriteLine("  Seeded EncryptedNoEnclave (5 rows)");

        // Seed EncryptedWithEnclave — driver auto-encrypts via Column Encryption Setting
        await using (var enclaveConn = await OpenConnectionAsync(_enclaveConnectionString))
        {
            foreach (var row in rows)
                await InsertRowAsync(enclaveConn, "dbo.EncryptedWithEnclave", row.SSN, row.FullName, row.Salary);
        }
        System.Console.WriteLine("  Seeded EncryptedWithEnclave (5 rows)");

        System.Console.WriteLine();
    }

    private static async Task InsertRowAsync(SqlConnection connection, string tableName, string ssn, string fullName, decimal salary)
    {
        await using var cmd = new SqlCommand(InsertSpMap[tableName], connection);
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.Parameters.Add(new SqlParameter("@SSN", SqlDbType.Char, 11) { Value = ssn });
        cmd.Parameters.Add(new SqlParameter("@FullName", SqlDbType.NVarChar, 100) { Value = fullName });
        cmd.Parameters.Add(new SqlParameter("@Salary", SqlDbType.Money) { Value = salary });
        await cmd.ExecuteNonQueryAsync();
    }

    // ========================================================================
    // Test 1: Retrieve data from all 3 tables
    // ========================================================================

    public async Task Test1_RetrieveAllDataAsync()
    {
        System.Console.WriteLine("=== Test 1: Retrieve Data from All 3 Tables ===\n");
        System.Console.WriteLine("  Expected: 5 rows per table, all matching seeded data.");
        System.Console.WriteLine("  Expect Id=1 Catherine Abel $31,692.00, Id=2 Kim Abercrombie $55,415.00,");
        System.Console.WriteLine("         Id=3 John Smith $72,000.00, Id=4 Maria Garcia $89,500.00, Id=5 Robert Johnson $45,000.00\n");

        await using (var plainConn = await OpenConnectionAsync(_plainConnectionString))
        {
            System.Console.WriteLine("--- PlainData (no encryption, baseline) ---");
            await PrintTableAsync(plainConn, "dbo.PlainData");
        }

        await using (var aeConn = await OpenConnectionAsync(_aeConnectionString))
        {
            System.Console.WriteLine("--- EncryptedNoEnclave (decrypted by driver via Column Encryption Setting) ---");
            await PrintTableAsync(aeConn, "dbo.EncryptedNoEnclave");
        }

        await using (var enclaveConn = await OpenConnectionAsync(_enclaveConnectionString))
        {
            System.Console.WriteLine("--- EncryptedWithEnclave (decrypted by driver via enclave connection) ---");
            await PrintTableAsync(enclaveConn, "dbo.EncryptedWithEnclave");
        }

        System.Console.WriteLine();
    }

    // ========================================================================
    // Test 2: Move encrypted (no enclave) data via stored procedure
    // ========================================================================

    public async Task Test2_MoveEncryptedNoEnclaveDataAsync()
    {
        System.Console.WriteLine("=== Test 2: Move Encrypted Data (No Enclave) via SP ===\n");
        System.Console.WriteLine("  Action: Executing dbo.usp_MoveEncryptedNoEnclaveData");
        System.Console.WriteLine("  This SP copies all 5 rows from EncryptedNoEnclave → EncryptedNoEnclave_Target.");
        System.Console.WriteLine("  Copies raw ciphertext (same CEK on source and target, no decryption needed).");
        System.Console.WriteLine("  Expected: Target table should contain all 5 seeded rows with identical plaintext values.\n");

        await using var connection = await OpenConnectionAsync(_aeConnectionString);

        await using (var cmd = new SqlCommand("dbo.usp_MoveEncryptedNoEnclaveData", connection))
        {
            cmd.CommandType = CommandType.StoredProcedure;
            await cmd.ExecuteNonQueryAsync();
        }

        System.Console.WriteLine("  SP executed. Verifying EncryptedNoEnclave_Target (expect 5 rows):");
        await PrintTableAsync(connection, "dbo.EncryptedNoEnclave_Target");

        System.Console.WriteLine();
    }

    // ========================================================================
    // Test 3: Move encrypted (with enclave) data via stored procedure
    // ========================================================================

    public async Task Test3_MoveEncryptedWithEnclaveDataAsync()
    {
        System.Console.WriteLine("=== Test 3: Move Encrypted Data (With Enclave) via SP ===\n");
        System.Console.WriteLine("  Action: Executing dbo.usp_MoveEncryptedWithEnclaveData");
        System.Console.WriteLine("  This SP copies all 5 rows from EncryptedWithEnclave → EncryptedWithEnclave_Target.");
        System.Console.WriteLine("  Copies ciphertext (same enclave-enabled CEK on source and target).");
        System.Console.WriteLine("  Expected: Target table should contain all 5 seeded rows with identical plaintext values.\n");

        await using var connection = await OpenConnectionAsync(_enclaveConnectionString);

        await using (var cmd = new SqlCommand("dbo.usp_MoveEncryptedWithEnclaveData", connection))
        {
            cmd.CommandType = CommandType.StoredProcedure;
            await cmd.ExecuteNonQueryAsync();
        }

        System.Console.WriteLine("  SP executed. Verifying EncryptedWithEnclave_Target (expect 5 rows):");
        await PrintTableAsync(connection, "dbo.EncryptedWithEnclave_Target");

        System.Console.WriteLine();
    }

    // ========================================================================
    // Test 4: SUBSTRING on non-enclave encrypted data (EXPECTED FAILURE)
    // ========================================================================

    public async Task Test4_SubstringNoEnclaveAsync()
    {
        System.Console.WriteLine("=== Test 4: SUBSTRING on Encrypted Data (No Enclave) — Expected Failure ===\n");
        System.Console.WriteLine("  Action: Executing SUBSTRING(SSN, 1, 3) on EncryptedNoEnclave via dbo.usp_SubstringNoEnclave");
        System.Console.WriteLine("  This attempts to compute SUBSTRING on non-enclave encrypted columns.");
        System.Console.WriteLine("  Expected: SqlException — server cannot perform SUBSTRING on ciphertext without enclave.");
        System.Console.WriteLine("  If it somehow succeeded, the 5 SSN prefixes would be: 795, 990, 123, 987, 555\n");

        try
        {
            await using var connection = await OpenConnectionAsync(_aeConnectionString);
            await using var cmd = new SqlCommand("dbo.usp_SubstringNoEnclave", connection);
            cmd.CommandType = CommandType.StoredProcedure;

            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                System.Console.WriteLine($"  Id={reader["Id"]}, SSN_Prefix={reader["SSN_Prefix"]}");
            }

            System.Console.WriteLine("  UNEXPECTED: No error was thrown!");
        }
        catch (SqlException ex)
        {
            System.Console.WriteLine($"  EXPECTED ERROR: {ex.Message}");
            System.Console.WriteLine("  >> SUBSTRING is not supported on encrypted columns without enclave.");
        }

        System.Console.WriteLine();
    }

    // ========================================================================
    // Test 5: SUBSTRING on enclave-enabled encrypted data (EXPECTED SUCCESS)
    // ========================================================================

    public async Task Test5_SubstringWithEnclaveAsync()
    {
        System.Console.WriteLine("=== Test 5: SUBSTRING on Encrypted Data (With Enclave) — Expected Success ===\n");
        System.Console.WriteLine("  Action: Executing SUBSTRING(SSN,1,3) and SUBSTRING(FullName,1,5) on EncryptedWithEnclave");
        System.Console.WriteLine("  via dbo.usp_SubstringWithEnclave (uses sp_executesql for enclave session).");
        System.Console.WriteLine("  Expected 5 rows:");
        System.Console.WriteLine("    Id=1, SSN_Prefix=795, Name_Prefix=Cathe  (Catherine Abel)");
        System.Console.WriteLine("    Id=2, SSN_Prefix=990, Name_Prefix=Kim A  (Kim Abercrombie)");
        System.Console.WriteLine("    Id=3, SSN_Prefix=123, Name_Prefix=John   (John Smith)");
        System.Console.WriteLine("    Id=4, SSN_Prefix=987, Name_Prefix=Maria  (Maria Garcia)");
        System.Console.WriteLine("    Id=5, SSN_Prefix=555, Name_Prefix=Rober  (Robert Johnson)\n");

        // Pre-flight: check if the VBS enclave is actually loaded on the server.
        await using (var diagConn = await OpenConnectionAsync(_plainConnectionString))
        {
            await using var enclCmd = new SqlCommand(
                "SELECT * FROM sys.dm_column_encryption_enclave;", diagConn);
            await using var enclReader = await enclCmd.ExecuteReaderAsync();
            if (!enclReader.HasRows)
            {
                System.Console.WriteLine("  WARNING: sys.dm_column_encryption_enclave returned 0 rows — VBS enclave is NOT loaded!");
                System.Console.WriteLine("  Enclave queries will fail until the enclave is loaded on the Azure SQL server.");
                System.Console.WriteLine("  Verify: database has preferredEnclaveType='VBS', SKU is GP_Gen5 (vCore), and region supports VBS.\n");
            }
            else
            {
                while (await enclReader.ReadAsync())
                {
                    var vals = string.Join(", ", Enumerable.Range(0, enclReader.FieldCount)
                        .Select(i => $"{enclReader.GetName(i)}={enclReader.GetValue(i)}"));
                    System.Console.WriteLine($"  Enclave DMV: {vals}");
                }
            }
        }

        try
        {
            await using var connection = await OpenConnectionAsync(_enclaveConnectionString);

            // The SP uses dynamic SQL (sp_executesql) which triggers enclave session
            // establishment when the server detects SUBSTRING on enclave-enabled columns.
            await using var cmd = new SqlCommand("dbo.usp_SubstringWithEnclave", connection);
            cmd.CommandType = CommandType.StoredProcedure;

            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                System.Console.WriteLine($"  Id={reader["Id"]}, SSN_Prefix={reader["SSN_Prefix"]}, Name_Prefix={reader["Name_Prefix"]}");
            }

            System.Console.WriteLine("  SUCCESS: Enclave SUBSTRING completed.\n");
        }
        catch (SqlException ex)
        {
            System.Console.WriteLine($"  FAILED: {ex.Message}");
            System.Console.WriteLine("  >> The VBS enclave session could not be established.");
            System.Console.WriteLine("  >> Verify the enclave is loaded (sys.dm_column_encryption_enclave should have rows).\n");
        }
    }

    // ========================================================================
    // Test 6: Update a row using an encrypted field
    // ========================================================================

    public async Task Test6_UpdateEncryptedFieldAsync()
    {
        System.Console.WriteLine("=== Test 6: Update Encrypted Field (Salary) ===\n");
        System.Console.WriteLine("  Tests parameterized UPDATE on encrypted Salary column (filtered by unencrypted Id).\n");

        // Update row Id=1 in EncryptedNoEnclave (AE connection, no enclave needed)
        await using (var aeConn = await OpenConnectionAsync(_aeConnectionString))
        {
            System.Console.WriteLine("  Updating Id=1 (Catherine Abel, SSN=795-73-9838) in EncryptedNoEnclave:");
            System.Console.WriteLine("    Salary: $31,692.00 → $99,999.00 (via dbo.usp_UpdateSalaryEncryptedNoEnclave)");
            await UpdateSalaryAsync(aeConn, "dbo.EncryptedNoEnclave", 1, 99999.00m);

            System.Console.WriteLine("  Verifying EncryptedNoEnclave — expect Id=1 Salary=$99,999.00, all other rows unchanged:");
            await PrintTableAsync(aeConn, "dbo.EncryptedNoEnclave");
        }

        // Update row Id=1 in EncryptedWithEnclave (enclave connection)
        await using (var enclaveConn = await OpenConnectionAsync(_enclaveConnectionString))
        {
            System.Console.WriteLine("  Updating Id=1 (Catherine Abel, SSN=795-73-9838) in EncryptedWithEnclave:");
            System.Console.WriteLine("    Salary: $31,692.00 → $88,888.00 (via dbo.usp_UpdateSalaryEncryptedWithEnclave)");
            await UpdateSalaryAsync(enclaveConn, "dbo.EncryptedWithEnclave", 1, 88888.00m);

            System.Console.WriteLine("  Verifying EncryptedWithEnclave — expect Id=1 Salary=$88,888.00, all other rows unchanged:");
            await PrintTableAsync(enclaveConn, "dbo.EncryptedWithEnclave");
        }

        System.Console.WriteLine();
    }

    private static async Task UpdateSalaryAsync(SqlConnection connection, string tableName, int id, decimal newSalary)
    {
        await using var cmd = new SqlCommand(UpdateSalarySpMap[tableName], connection);
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.Parameters.Add(new SqlParameter("@NewSalary", SqlDbType.Money) { Value = newSalary });
        cmd.Parameters.Add(new SqlParameter("@Id", SqlDbType.Int) { Value = id });
        var affected = await cmd.ExecuteNonQueryAsync();
        System.Console.WriteLine($"  Rows affected: {affected}");
    }

    // ========================================================================
    // Test 7: Equality query on encrypted fields
    // ========================================================================

    public async Task Test7_EqualityQueryAsync()
    {
        System.Console.WriteLine("=== Test 7: Equality Queries on Encrypted Fields ===\n");
        System.Console.WriteLine("  Tests WHERE clauses on encrypted columns. Note: Test 6 changed Id=1 Salary,");
        System.Console.WriteLine("  but queries below filter by Id=2 (Kim Abercrombie) so Salary should still be $55,415.00.\n");

        // 7a: Deterministic equality on non-enclave table (should succeed)
        await using (var aeConn = await OpenConnectionAsync(_aeConnectionString))
        {
            System.Console.WriteLine("--- 7a: WHERE SSN = '990-00-6818' on EncryptedNoEnclave (Deterministic, No Enclave) ---");
            System.Console.WriteLine("  Filtering by: SSN='990-00-6818' via dbo.usp_QueryBySsnEncryptedNoEnclave");
            System.Console.WriteLine("  Expected: 1 row — Id=2, SSN=990-00-6818, FullName=Kim Abercrombie, Salary=$55,415.00");
            await QueryBySsnAsync(aeConn, "dbo.EncryptedNoEnclave", "990-00-6818");
        }

        System.Console.WriteLine();

        // 7b: Deterministic equality on enclave table (should succeed)
        await using (var enclaveConn = await OpenConnectionAsync(_enclaveConnectionString))
        {
            System.Console.WriteLine("--- 7b: WHERE SSN = '990-00-6818' on EncryptedWithEnclave (Deterministic, With Enclave) ---");
            System.Console.WriteLine("  Filtering by: SSN='990-00-6818' via dbo.usp_QueryBySsnEncryptedWithEnclave");
            System.Console.WriteLine("  Expected: 1 row — Id=2, SSN=990-00-6818, FullName=Kim Abercrombie, Salary=$55,415.00");
            await QueryBySsnAsync(enclaveConn, "dbo.EncryptedWithEnclave", "990-00-6818");

            // 7d: Randomized equality on enclave table (should succeed)
            System.Console.WriteLine("--- 7d: WHERE FullName = 'Kim Abercrombie' on EncryptedWithEnclave (Deterministic, With Enclave) — Expected Success ---");
            System.Console.WriteLine("  Filtering by: FullName='Kim Abercrombie' via dbo.usp_QueryByFullNameEncryptedWithEnclave");
            System.Console.WriteLine("  Expected: 1 row — Id=2, SSN=990-00-6818, FullName=Kim Abercrombie, Salary=$55,415.00");
            await QueryByFullNameAsync(enclaveConn, "dbo.EncryptedWithEnclave", "Kim Abercrombie");
        }

        System.Console.WriteLine();

        // 7c: Randomized equality on non-enclave table (should FAIL)
        System.Console.WriteLine("--- 7c: WHERE FullName = 'Kim Abercrombie' on EncryptedNoEnclave (Deterministic, No Enclave) — Expected Failure ---");
        await using (var plainConn = await OpenConnectionAsync(_plainConnectionString))
        {
            System.Console.WriteLine("  Filtering by: FullName='Kim Abercrombie' via dbo.usp_QueryByFullNameEncryptedNoEnclave");
            System.Console.WriteLine("  Expected: SqlException — equality on deterministic columns without enclave may fail depending on config.");
            try
            {
                await QueryByFullNameAsync(plainConn, "dbo.EncryptedNoEnclave", "Kim Abercrombie");
                System.Console.WriteLine("  UNEXPECTED: No error was thrown!");
            }
            catch (SqlException ex)
            {
                System.Console.WriteLine($"  EXPECTED ERROR: {ex.Message}");
                System.Console.WriteLine("  >> Equality on randomized columns is not supported without enclave.");
            }
        }

        System.Console.WriteLine();
    }

    private static async Task QueryBySsnAsync(SqlConnection connection, string tableName, string ssn)
    {
        await using var cmd = new SqlCommand(QueryBySsnSpMap[tableName], connection);
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.Parameters.Add(new SqlParameter("@SSN", SqlDbType.Char, 11) { Value = ssn });

        await using var reader = await cmd.ExecuteReaderAsync();
        var found = false;
        while (await reader.ReadAsync())
        {
            found = true;
            System.Console.WriteLine($"  Id={reader["Id"]}, SSN={reader["SSN"]}, FullName={reader["FullName"]}, Salary={reader["Salary"]:C}");
        }
        if (!found) System.Console.WriteLine("  No rows returned.");
    }

    private static async Task QueryByFullNameAsync(SqlConnection connection, string tableName, string fullName)
    {
        await using var cmd = new SqlCommand(QueryByFullNameSpMap[tableName], connection);
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.Parameters.Add(new SqlParameter("@FullName", SqlDbType.NVarChar, 100) { Value = fullName });

        await using var reader = await cmd.ExecuteReaderAsync();
        var found = false;
        while (await reader.ReadAsync())
        {
            found = true;
            System.Console.WriteLine($"  Id={reader["Id"]}, SSN={reader["SSN"]}, FullName={reader["FullName"]}, Salary={reader["Salary"]:C}");
        }
        if (!found) System.Console.WriteLine("  No rows returned.");
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    private static async Task<SqlConnection> OpenConnectionAsync(string connectionString)
    {
        var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();
        return connection;
    }

    private static async Task PrintTableAsync(SqlConnection connection, string tableName)
    {
        await using var cmd = new SqlCommand(GetAllSpMap[tableName], connection);
        cmd.CommandType = CommandType.StoredProcedure;
        await using var reader = await cmd.ExecuteReaderAsync();

        while (await reader.ReadAsync())
        {
            var values = new List<string>();
            for (int i = 0; i < reader.FieldCount; i++)
            {
                var name = reader.GetName(i);
                var value = reader.IsDBNull(i) ? "NULL" : reader[i] is decimal d ? d.ToString("C") : reader[i]?.ToString() ?? "NULL";
                values.Add($"{name}={value}");
            }
            System.Console.WriteLine($"  {string.Join(", ", values)}");
        }
    }
}
