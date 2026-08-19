SET XACT_ABORT ON;
BEGIN TRANSACTION;

/*
   Bổ sung loại phát sinh ALLOWANCE (phụ cấp) cho bảng lương đã triển khai.
   Chỉ thay ràng buộc kiểm tra trên cột adjustment_type, không làm mất lịch sử phát sinh.
*/
IF OBJECT_ID(N'dbo.employee_payroll_adjustments', N'U') IS NOT NULL
BEGIN
    DECLARE @DropPayrollAdjustmentConstraintSql NVARCHAR(MAX) = N'';
    SELECT @DropPayrollAdjustmentConstraintSql = @DropPayrollAdjustmentConstraintSql
        + N'ALTER TABLE dbo.employee_payroll_adjustments DROP CONSTRAINT ' + QUOTENAME(name) + N';'
    FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.employee_payroll_adjustments')
      AND definition LIKE N'%adjustment_type%'
      AND definition LIKE N'%BONUS%'
      AND definition LIKE N'%DEDUCTION%'
      AND definition NOT LIKE N'%ALLOWANCE%';
    IF LEN(@DropPayrollAdjustmentConstraintSql) > 0 EXEC sys.sp_executesql @DropPayrollAdjustmentConstraintSql;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.employee_payroll_adjustments')
          AND definition LIKE N'%adjustment_type%'
          AND definition LIKE N'%ALLOWANCE%'
          AND definition LIKE N'%BONUS%'
          AND definition LIKE N'%DEDUCTION%'
    )
        ALTER TABLE dbo.employee_payroll_adjustments WITH CHECK
        ADD CONSTRAINT CK_employee_payroll_adjustments_type CHECK(adjustment_type IN (N'ALLOWANCE', N'BONUS', N'DEDUCTION'));
END;

COMMIT TRANSACTION;
