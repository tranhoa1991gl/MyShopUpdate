SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    /*
       Đồng bộ các khoản ứng/chi lương đã phát sinh với Sổ quỹ.
       Không tạo bảng mới: mỗi khoản chi lương dùng chứng từ PAYROLL:<payment_id>.
       Script có thể chạy lặp lại an toàn; chỉ bổ sung phiếu còn thiếu và xóa mềm
       phiếu có nguồn chi lương đã bị hủy.
    */
    IF OBJECT_ID(N'dbo.employee_payroll_payments', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.employee_payrolls', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.cashbook_entries', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.cashbook_categories', N'U') IS NOT NULL
    BEGIN
        DECLARE @HasAffectsProfit BIT = CASE
            WHEN COL_LENGTH(N'dbo.cashbook_categories', N'affects_profit') IS NOT NULL THEN 1
            ELSE 0
        END;

        /* Danh mục hệ thống cho hai loại chi lương. */
        IF @HasAffectsProfit = 1
        BEGIN
            UPDATE dbo.cashbook_categories
            SET is_system = 1,
                is_active = 1,
                affects_profit = 1,
                sort_order = CASE
                    WHEN category_name = N'Tạm ứng lương nhân viên' THEN 95
                    ELSE 96
                END
            WHERE category_type = N'OUT'
              AND category_name IN (N'Tạm ứng lương nhân viên', N'Chi lương nhân viên');
        END
        ELSE
        BEGIN
            UPDATE dbo.cashbook_categories
            SET is_system = 1,
                is_active = 1,
                sort_order = CASE
                    WHEN category_name = N'Tạm ứng lương nhân viên' THEN 95
                    ELSE 96
                END
            WHERE category_type = N'OUT'
              AND category_name IN (N'Tạm ứng lương nhân viên', N'Chi lương nhân viên');
        END;

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.cashbook_categories
            WHERE category_type = N'OUT' AND category_name = N'Tạm ứng lương nhân viên'
        )
        BEGIN
            IF @HasAffectsProfit = 1
                INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, is_active, affects_profit, sort_order)
                VALUES(N'OUT', N'Tạm ứng lương nhân viên', 1, 1, 1, 95);
            ELSE
                INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, is_active, sort_order)
                VALUES(N'OUT', N'Tạm ứng lương nhân viên', 1, 1, 95);
        END;

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.cashbook_categories
            WHERE category_type = N'OUT' AND category_name = N'Chi lương nhân viên'
        )
        BEGIN
            IF @HasAffectsProfit = 1
                INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, is_active, affects_profit, sort_order)
                VALUES(N'OUT', N'Chi lương nhân viên', 1, 1, 1, 96);
            ELSE
                INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, is_active, sort_order)
                VALUES(N'OUT', N'Chi lương nhân viên', 1, 1, 96);
        END;

        DECLARE @AdvanceCategoryId INT;
        DECLARE @SettlementCategoryId INT;
        SELECT TOP 1 @AdvanceCategoryId = category_id
        FROM dbo.cashbook_categories
        WHERE category_type = N'OUT' AND category_name = N'Tạm ứng lương nhân viên'
        ORDER BY category_id;
        SELECT TOP 1 @SettlementCategoryId = category_id
        FROM dbo.cashbook_categories
        WHERE category_type = N'OUT' AND category_name = N'Chi lương nhân viên'
        ORDER BY category_id;

        /* Backfill phiếu đang hiệu lực mà Sổ quỹ chưa có. */
        INSERT INTO dbo.cashbook_entries
        (
            entry_date,
            entry_type,
            category_id,
            category_name,
            amount,
            payment_method,
            description,
            reference_code,
            created_by
        )
        SELECT
            pp.payment_date,
            N'OUT',
            CASE WHEN pp.payment_type = N'ADVANCE' THEN @AdvanceCategoryId ELSE @SettlementCategoryId END,
            CASE WHEN pp.payment_type = N'ADVANCE' THEN N'Tạm ứng lương nhân viên' ELSE N'Chi lương nhân viên' END,
            pp.amount,
            ISNULL(NULLIF(LTRIM(RTRIM(pp.payment_method)), N''), N'Tiền mặt'),
            CASE WHEN pp.payment_type = N'ADVANCE' THEN N'Tạm ứng lương: ' ELSE N'Thanh toán lương: ' END
                + ISNULL(NULLIF(LTRIM(RTRIM(p.employee_name)), N''), N'nhân viên'),
            N'PAYROLL:' + CONVERT(NVARCHAR(20), pp.payment_id),
            NULLIF(LTRIM(RTRIM(pp.created_by)), N'')
        FROM dbo.employee_payroll_payments pp
        INNER JOIN dbo.employee_payrolls p ON p.payroll_id = pp.payroll_id
        WHERE pp.is_void = 0
          AND pp.amount > 0
          AND pp.payment_type IN (N'ADVANCE', N'SETTLEMENT')
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.cashbook_entries ce WITH (UPDLOCK, HOLDLOCK)
              WHERE ce.is_deleted = 0
                AND ce.reference_code = N'PAYROLL:' + CONVERT(NVARCHAR(20), pp.payment_id)
          );

        /* Mã phiếu cho các dòng được backfill trên database cũ. */
        UPDATE ce
        SET entry_code = N'SQ' + CONVERT(CHAR(6), ce.entry_date, 12)
            + RIGHT(N'000000' + CONVERT(NVARCHAR(20), ce.entry_id), 6),
            updated_at = GETDATE()
        FROM dbo.cashbook_entries ce
        WHERE ce.is_deleted = 0
          AND ce.reference_code LIKE N'PAYROLL:%'
          AND NULLIF(LTRIM(RTRIM(ce.entry_code)), N'') IS NULL;

        /* Hủy đồng bộ phiếu quỹ nếu khoản ứng/chi nguồn đã hủy. */
        UPDATE ce
        SET is_deleted = 1,
            updated_at = GETDATE()
        FROM dbo.cashbook_entries ce
        INNER JOIN dbo.employee_payroll_payments pp
            ON ce.reference_code = N'PAYROLL:' + CONVERT(NVARCHAR(20), pp.payment_id)
        WHERE ce.is_deleted = 0
          AND pp.is_void = 1;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
