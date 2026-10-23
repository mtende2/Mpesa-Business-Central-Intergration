pageextension 50100 "MPESA Posted Sales Invoice" extends "Posted Sales Invoice"
{
    actions
    {
        addlast(processing)
        {
            action(RequestMpesaPayment)
            {
                ApplicationArea = All;
                Caption = 'Request M-Pesa Payment';
                Image = Payment;
                ToolTip = 'Sends an M-Pesa STK Push prompt to the customer''s phone for the remaining amount on this invoice.';

                trigger OnAction()
                var
                    Customer: Record Customer;
                    MpesaApiMgt: Codeunit "MPESA API Mgt.";
                    PhoneNo: Text;
                begin
                    Rec.CalcFields("Remaining Amount");
                    if Rec."Remaining Amount" <= 0 then
                        Error(NothingToPayErr, Rec."No.");

                    Customer.Get(Rec."Bill-to Customer No.");
                    PhoneNo := Customer."Mobile Phone No.";
                    if PhoneNo = '' then
                        PhoneNo := Customer."Phone No.";
                    if PhoneNo = '' then
                        Error(NoPhoneErr, Customer."No.");

                    if not Confirm(ConfirmQst, false, Rec."Remaining Amount", PhoneNo) then
                        exit;

                    MpesaApiMgt.InitiateStkPush(PhoneNo, Rec."Remaining Amount", Rec."No.", Rec."Bill-to Customer No.", Rec."No.");
                    Message(SentMsg, PhoneNo);
                end;
            }
            action(MpesaTransactions)
            {
                ApplicationArea = All;
                Caption = 'M-Pesa Transactions';
                Image = Payment;
                RunObject = page "MPESA Transactions";
                RunPageLink = "Document No." = field("No.");
                ToolTip = 'Shows M-Pesa payments linked to this invoice.';
            }
        }
    }

    var
        NothingToPayErr: Label 'Invoice %1 has no remaining amount to collect.', Comment = '%1 = invoice no.';
        NoPhoneErr: Label 'Customer %1 has no mobile phone number.', Comment = '%1 = customer no.';
        ConfirmQst: Label 'Send an M-Pesa payment request of KES %1 to %2?', Comment = '%1 = amount, %2 = phone';
        SentMsg: Label 'Payment request sent. The customer will see an M-Pesa prompt on %1.', Comment = '%1 = phone';
}
