enum 50100 "MPESA Trans. Status"
{
    Extensible = true;
    Caption = 'M-Pesa Transaction Status';

    value(0; Pending) { Caption = 'Pending'; }
    value(1; Completed) { Caption = 'Completed'; }
    value(2; Failed) { Caption = 'Failed'; }
    value(3; Unmatched) { Caption = 'Unmatched'; }
    value(4; Posted) { Caption = 'Posted'; }
    value(5; Error) { Caption = 'Error'; }
}

enum 50101 "MPESA Trans. Type"
{
    Extensible = true;
    Caption = 'M-Pesa Transaction Type';

    value(0; "STK Push") { Caption = 'STK Push'; }
    value(1; C2B) { Caption = 'C2B (PayBill)'; }
}

enum 50102 "MPESA Environment"
{
    Extensible = false;
    Caption = 'M-Pesa Environment';

    value(0; Sandbox) { Caption = 'Sandbox'; }
    value(1; Production) { Caption = 'Production'; }
}
