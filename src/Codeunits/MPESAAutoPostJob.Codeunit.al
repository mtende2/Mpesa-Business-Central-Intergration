codeunit 50103 "MPESA Auto Post Job"
{
    // Run from the job queue. Posts every completed, customer-matched payment.

    trigger OnRun()
    var
        Setup: Record "MPESA Setup";
        MpesaPostingMgt: Codeunit "MPESA Posting Mgt.";
    begin
        if not Setup.Get() then
            exit;
        if not Setup."Auto Post Payments" then
            exit;
        MpesaPostingMgt.PostAllReady();
    end;
}
