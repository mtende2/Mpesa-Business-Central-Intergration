permissionset 50100 "MPESA ALL"
{
    Assignable = true;
    Caption = 'M-Pesa Payments - All';

    Permissions =
        tabledata "MPESA Setup" = RIMD,
        tabledata "MPESA Transaction" = RIMD,
        table "MPESA Setup" = X,
        table "MPESA Transaction" = X,
        codeunit "MPESA API Mgt." = X,
        codeunit "MPESA Posting Mgt." = X,
        codeunit "MPESA Post Transaction" = X,
        codeunit "MPESA Auto Post Job" = X,
        page "MPESA Setup" = X,
        page "MPESA Transactions" = X,
        page "MPESA Transaction API" = X;
}
