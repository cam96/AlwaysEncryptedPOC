using AlwaysEncryptPOC.Console;
using Azure.Identity;
using Microsoft.Data.SqlClient;
using Microsoft.Data.SqlClient.AlwaysEncrypted.AzureKeyVaultProvider;
using Microsoft.Extensions.Configuration;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
var config = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: false)
    .AddUserSecrets<Program>(optional: true)
    .Build();

var plainConnStr = config.GetConnectionString("SqlPlain")
    ?? throw new InvalidOperationException("Missing 'SqlPlain' connection string in appsettings.json.");
var aeConnStr = config.GetConnectionString("SqlAlwaysEncrypted")
    ?? throw new InvalidOperationException("Missing 'SqlAlwaysEncrypted' connection string in appsettings.json.");
var enclaveConnStr = config.GetConnectionString("SqlAlwaysEncryptedWithEnclave")
    ?? throw new InvalidOperationException("Missing 'SqlAlwaysEncryptedWithEnclave' connection string in appsettings.json.");

// ---------------------------------------------------------------------------
// Register Azure Key Vault provider for Always Encrypted
// ---------------------------------------------------------------------------
// This enables the SqlClient driver to unwrap Column Encryption Keys using
// the RSA keys stored in Azure Key Vault via DefaultAzureCredential.
var akvProvider = new SqlColumnEncryptionAzureKeyVaultProvider(new DefaultAzureCredential());
SqlConnection.RegisterColumnEncryptionKeyStoreProviders(
    new Dictionary<string, SqlColumnEncryptionKeyStoreProvider>
    {
        { SqlColumnEncryptionAzureKeyVaultProvider.ProviderName, akvProvider }
    });

Console.WriteLine("╔══════════════════════════════════════════════════════════╗");
Console.WriteLine("║   Always Encrypted POC — Azure SQL with VBS Enclaves     ║");
Console.WriteLine("╚══════════════════════════════════════════════════════════╝");
Console.WriteLine();

// ---------------------------------------------------------------------------
// Reset & recreate database objects (tables + stored procedures)
// ---------------------------------------------------------------------------
Console.WriteLine("=== Setting up database (reset → tables → stored procedures) ===\n");
await RunSqlScriptAsync(plainConnStr, Path.Combine(AppContext.BaseDirectory, "sql", "00-ResetDatabase.sql"));
await RunSqlScriptAsync(plainConnStr, Path.Combine(AppContext.BaseDirectory, "sql", "03-CreateTables.sql"));
await RunSqlScriptAsync(plainConnStr, Path.Combine(AppContext.BaseDirectory, "sql", "04-StoredProcedures.sql"));
Console.WriteLine("  Database setup complete.\n");

// ---------------------------------------------------------------------------
// Diagnostic: Check enclave & CMK configuration
// ---------------------------------------------------------------------------
Console.WriteLine("=== Diagnostic: Enclave & CMK Configuration ===\n");
{
    await using var diagConn = new SqlConnection(plainConnStr);
    await diagConn.OpenAsync();

    await using var cmd1 = new SqlCommand(
        "SELECT name, allow_enclave_computations FROM sys.column_master_keys;", diagConn);
    await using var r1 = await cmd1.ExecuteReaderAsync();
    while (await r1.ReadAsync())
        Console.WriteLine($"  CMK: {r1["name"]}, allow_enclave_computations={r1["allow_enclave_computations"]}");
    await r1.CloseAsync();

    // Check if the enclave is loaded on the server (discover schema dynamically)
    try
    {
        await using var cmd3 = new SqlCommand(
            "SELECT * FROM sys.dm_column_encryption_enclave;", diagConn);
        await using var r3 = await cmd3.ExecuteReaderAsync();
        var cols = string.Join(", ", Enumerable.Range(0, r3.FieldCount).Select(i => r3.GetName(i)));
        Console.WriteLine($"  Enclave DMV columns: [{cols}]");
        if (await r3.ReadAsync())
        {
            var vals = string.Join(", ", Enumerable.Range(0, r3.FieldCount).Select(i => $"{r3.GetName(i)}={r3.GetValue(i)}"));
            Console.WriteLine($"  Enclave DMV row: {vals}");
        }
        else
            Console.WriteLine("  WARNING: sys.dm_column_encryption_enclave returned 0 rows — enclave NOT loaded!");
        await r3.CloseAsync();
    }
    catch (Exception ex)
    {
        Console.WriteLine($"  Enclave DMV error: {ex.Message}");
    }

    // Check CMK details - discover all columns
    try
    {
        await using var cmdSig = new SqlCommand("SELECT * FROM sys.column_master_keys WHERE allow_enclave_computations = 1;", diagConn);
        await using var rSig = await cmdSig.ExecuteReaderAsync();
        var cols = string.Join(", ", Enumerable.Range(0, rSig.FieldCount).Select(i => rSig.GetName(i)));
        Console.WriteLine($"  sys.column_master_keys columns: [{cols}]");
        while (await rSig.ReadAsync())
        {
            var vals = string.Join(", ", Enumerable.Range(0, rSig.FieldCount).Select(i =>
                rSig.IsDBNull(i) ? $"{rSig.GetName(i)}=NULL"
                    : rSig.GetValue(i) is byte[] b ? $"{rSig.GetName(i)}=[{b.Length} bytes]"
                    : $"{rSig.GetName(i)}={rSig.GetValue(i)}"));
            Console.WriteLine($"  CMK row: {vals}");
        }
        await rSig.CloseAsync();
    }
    catch (Exception ex)
    {
        Console.WriteLine($"  CMK check error: {ex.Message}");
    }

    // Verify CMK signature using the AKV provider
    try
    {
        await using var cmdKey = new SqlCommand(
            "SELECT key_store_provider_name, key_path, signature FROM sys.column_master_keys WHERE name = 'CMK_WithEnclave'", diagConn);
        await using var rKey = await cmdKey.ExecuteReaderAsync();
        if (await rKey.ReadAsync())
        {
            var keyPath = rKey.GetString(1);
            var signature = (byte[])rKey.GetValue(2);
            Console.WriteLine($"  CMK_WithEnclave key_path: {keyPath}");
            Console.WriteLine($"  CMK_WithEnclave signature: {signature.Length} bytes, first8={BitConverter.ToString(signature, 0, Math.Min(8, signature.Length))}");

            // Verify with actual stored signature
            var verified = akvProvider.VerifyColumnMasterKeyMetadata(keyPath, true, signature);
            Console.WriteLine($"  AKV provider VerifyColumnMasterKeyMetadata(allowEnclaveComputations=true, realSig): {verified}");

            // Also try signing fresh and compare
            var freshSig = akvProvider.SignColumnMasterKeyMetadata(keyPath, true);
            Console.WriteLine($"  Fresh signature: {freshSig.Length} bytes, first8={BitConverter.ToString(freshSig, 0, Math.Min(8, freshSig.Length))}");
            Console.WriteLine($"  Signatures match: {signature.SequenceEqual(freshSig)}");
        }
        await rKey.CloseAsync();
    }
    catch (Exception ex)
    {
        Console.WriteLine($"  CMK signature verify error: {ex.Message}");
    }

    // Check database-level enclave configuration
    try
    {
        await using var cmdCompat = new SqlCommand(
            "SELECT compatibility_level, collation_name FROM sys.databases WHERE name = DB_NAME()", diagConn);
        await using var rCompat = await cmdCompat.ExecuteReaderAsync();
        while (await rCompat.ReadAsync())
            Console.WriteLine($"  DB compatibility_level={rCompat["compatibility_level"]}, collation={rCompat["collation_name"]}");
        await rCompat.CloseAsync();
    }
    catch (Exception ex) { Console.WriteLine($"  Compat check error: {ex.Message}"); }

    // Test sp_describe_parameter_encryption WITH @enclaveType parameter
    // The enhanced version for enclaves requires @enclaveType=1 (VBS) to consider enclave operations
    try
    {
        await using var cmdSpDesc = new SqlCommand(
            "EXEC sp_describe_parameter_encryption " +
            "@tsql = N'SELECT Id, SUBSTRING(SSN, 1, 3) AS SSN_Prefix FROM dbo.EncryptedWithEnclave WHERE Id > @minId', " +
            "@params = N'@minId INT', " +
            "@enclaveType = 1;", diagConn);
        await using var rSpDesc = await cmdSpDesc.ExecuteReaderAsync();
        Console.Write("  sp_describe_parameter_encryption (enclaveType=1) result sets: ");
        int rsCount = 0;
        do
        {
            rsCount++;
            int rowCount = 0;
            while (await rSpDesc.ReadAsync()) rowCount++;
            Console.Write($"RS{rsCount}({rowCount} rows) ");
        } while (await rSpDesc.NextResultAsync());
        Console.WriteLine();
        await rSpDesc.CloseAsync();
    }
    catch (Exception ex)
    {
        Console.WriteLine($"  sp_describe_parameter_encryption (enclaveType=1) error: {ex.Message}");
    }

    // Verify the connection string is parsed correctly
    {
        var csb = new SqlConnectionStringBuilder(enclaveConnStr);
        Console.WriteLine($"  Parsed connection string:");
        Console.WriteLine($"    AttestationProtocol = {csb.AttestationProtocol}");
        Console.WriteLine($"    ColumnEncryptionSetting = {csb.ColumnEncryptionSetting}");
        Console.WriteLine($"    EnclaveAttestationUrl = '{csb.EnclaveAttestationUrl}'");
    }

    Console.WriteLine("  Testing enclave connection...");
    try
    {
        await using var enclConn = new SqlConnection(enclaveConnStr);
        await enclConn.OpenAsync();
        Console.WriteLine($"  Enclave connection opened successfully. ServerVersion={enclConn.ServerVersion}");

        // Try a simple enclave query
        await using var cmd5 = new SqlCommand(
            "SELECT SUBSTRING(SSN, 1, 3) AS SSN_Prefix FROM dbo.EncryptedWithEnclave", enclConn);
        await using var r5 = await cmd5.ExecuteReaderAsync();
        while (await r5.ReadAsync())
            Console.WriteLine($"    ENCLAVE QUERY SUCCESS: SSN_Prefix={r5["SSN_Prefix"]}");
        await r5.CloseAsync();
    }
    catch (SqlException ex)
    {
        Console.WriteLine($"  Enclave query FAILED: Error {ex.Number}: {ex.Message}");
    }
}
Console.WriteLine();

var tests = new DataTests(plainConnStr, aeConnStr, enclaveConnStr);

// ---------------------------------------------------------------------------
// Seed data into all 3 source tables
// ---------------------------------------------------------------------------
await tests.SeedDataAsync();

// ---------------------------------------------------------------------------
// Test 1: Retrieve data from all 3 tables (plain, encrypted-no-enclave, encrypted-with-enclave)
// ---------------------------------------------------------------------------
await tests.Test1_RetrieveAllDataAsync();

// ---------------------------------------------------------------------------
// Test 2: Move encrypted (no enclave) data via stored procedure
// ---------------------------------------------------------------------------
await tests.Test2_MoveEncryptedNoEnclaveDataAsync();

// ---------------------------------------------------------------------------
// Test 3: Move encrypted (with enclave) data via stored procedure
// ---------------------------------------------------------------------------
await tests.Test3_MoveEncryptedWithEnclaveDataAsync();

// ---------------------------------------------------------------------------
// Test 4: SUBSTRING on non-enclave encrypted data (expected failure)
// ---------------------------------------------------------------------------
await tests.Test4_SubstringNoEnclaveAsync();

// ---------------------------------------------------------------------------
// Test 5: SUBSTRING on enclave-enabled encrypted data (expected success)
// ---------------------------------------------------------------------------
await tests.Test5_SubstringWithEnclaveAsync();

// ---------------------------------------------------------------------------
// Test 6: Update a row using an encrypted field
// ---------------------------------------------------------------------------
await tests.Test6_UpdateEncryptedFieldAsync();

// ---------------------------------------------------------------------------
// Test 7: Equality queries on encrypted fields
// ---------------------------------------------------------------------------
await tests.Test7_EqualityQueryAsync();

Console.WriteLine("╔══════════════════════════════════════════════════════════╗");
Console.WriteLine("║                  All tests completed.                   ║");
Console.WriteLine("╚══════════════════════════════════════════════════════════╝");

// ---------------------------------------------------------------------------
// Helper: Execute a .sql file, splitting on GO batch separators
// ---------------------------------------------------------------------------
static async Task RunSqlScriptAsync(string connectionString, string scriptPath)
{
    var scriptText = await File.ReadAllTextAsync(scriptPath);

    // Split on GO lines (standalone, case-insensitive)
    var batches = System.Text.RegularExpressions.Regex.Split(scriptText, @"^\s*GO\s*$",
        System.Text.RegularExpressions.RegexOptions.Multiline | System.Text.RegularExpressions.RegexOptions.IgnoreCase);

    await using var connection = new SqlConnection(connectionString);
    await connection.OpenAsync();

    foreach (var batch in batches)
    {
        var trimmed = batch.Trim();
        if (string.IsNullOrEmpty(trimmed)) continue;

        await using var cmd = new SqlCommand(trimmed, connection);
        await cmd.ExecuteNonQueryAsync();
    }

    Console.WriteLine($"  Executed: {Path.GetFileName(scriptPath)}");
}
