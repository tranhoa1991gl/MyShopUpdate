-- Bổ sung cấu hình mặc định cho shop đã có bảng tích điểm theo sản phẩm.
IF OBJECT_ID(N'dbo.loyalty_point_settings', N'U') IS NOT NULL
BEGIN
    INSERT INTO dbo.loyalty_point_settings (id, is_enabled, fallback_mode, revision, updated_at)
    SELECT 1, 0, 'DEFAULT_RATE', 0, SYSDATETIME()
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.loyalty_point_settings WITH (UPDLOCK, HOLDLOCK)
        WHERE id = 1
    );
END;
