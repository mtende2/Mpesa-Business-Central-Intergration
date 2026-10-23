codeunit 50102 "MPESA Post Transaction"
{
    // Wrapper so a single payment can be posted inside Codeunit.Run,
    // which rolls back and captures the error instead of stopping a batch.
    TableNo = "MPESA Transaction";

    trigger OnRun()
    var
        MpesaPostingMgt: Codeunit "MPESA Posting Mgt.";
    begin
        MpesaPostingMgt.PostTransaction(Rec);
    end;
}
