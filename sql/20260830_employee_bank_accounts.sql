SET NOCOUNT ON;

IF COL_LENGTH(N'dbo.employees', N'bank_code') IS NULL
    ALTER TABLE dbo.employees ADD bank_code NVARCHAR(30) NULL;

IF COL_LENGTH(N'dbo.employees', N'bank_name') IS NULL
    ALTER TABLE dbo.employees ADD bank_name NVARCHAR(100) NULL;

IF COL_LENGTH(N'dbo.employees', N'bank_account') IS NULL
    ALTER TABLE dbo.employees ADD bank_account NVARCHAR(50) NULL;

IF COL_LENGTH(N'dbo.employees', N'bank_owner') IS NULL
    ALTER TABLE dbo.employees ADD bank_owner NVARCHAR(150) NULL;

