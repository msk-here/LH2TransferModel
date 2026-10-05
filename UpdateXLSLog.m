function UpdateXLSLog(var1,var2,path,dateandtime,Case,Topfill)

filename=path+"ResultsLog.xlsx";

% Obtaining Scenario and Method
CM=CaseMethod(Case);
TF=TopBottom(Topfill);

% Finding the index for when the process is considered finished.
if isempty(find(var2.ProcComp,1,'first'))
    F=size(var2.t,1); % If the flag for the process completed was not created, we take the last element
else
    F=round(find(var2.ProcComp,1,'first')*1); % We multiply the index by a factor of 1.1 to make sure the process has finished
%     if F>size(var2.t,1)
%         F=round(find(var2.ProcComp,1,'first')*1.05); % If F*1.1 exceeds index, we multiply the index by a factor of 1.05 to make sure the process has finished
%         if F>size(var2.t,1)
%             F=round(find(var2.ProcComp,1,'first')*1); % If F*1.05 exceeds index, we take F as it is.
%         end
%     end
end

% Obtaining column at which we will write the data
if CM.Scenario == "Trailer to Main"
    ColNumber= readmatrix(filename,"Sheet","Trailer to Main","Range","B37");
else
    ColNumber= readmatrix(filename,"Sheet","Main to On-board","Range","B37");
end
ColNumber=ColNumber(1);
NextColLetter=num2xlcol(ColNumber+1);

% Data to write
TopCell="Simulation "+(ColNumber-1);

if CM.Method=="Pump"
    NewColumn = [dateandtime;CM.Scenario;CM.Method;var2.t(F);(var2.mL2(F)+var2.mv2(F))-(var2.mL2(1)+var2.mv2(1));var2.Boiloff_ST(end);var2.Boiloff_ET(end);var2.Boiloff_ST(end)+var2.Boiloff_ET(end);(var2.Boiloff_ST(end)+var2.Boiloff_ET(end))/((var2.mL2(F)+var2.mv2(F))-(var2.mL2(1)+var2.mv2(1)));max(var2.Jtr);
                var2.pv2(F)/100000;var1.p20/100000;var2.hL2(F)/var1.H*100;(var2.mL2(F)+var2.mv2(F));var2.mL2(F);var2.mv2(F);var2.Tv2(F,end);var2.TL2(F,end);
                var2.pv1(F)/100000;var1.p10/100000;var2.hL1(F)/2*var1.R1*100;var2.mL1(F)+var2.mv1(F);var2.mL1(F);var2.mv1(F);var2.Tv1(F,end);var2.TL1(F,end);
                var1.VTotal1*1000;var1.VTotal2*1000;var1.p_ST_high/100000;var1.p_ET_high/100000;var1.namedetail;TF;var1.ConvCoeffTopfill;var1.TL10];
else
    NewColumn = [dateandtime;CM.Scenario;CM.Method;var2.t(F);(var2.mL2(F)+var2.mv2(F))-(var2.mL2(1)+var2.mv2(1));var2.Boiloff_ST(end);var2.Boiloff_ET(end);var2.Boiloff_ST(end)+var2.Boiloff_ET(end);(var2.Boiloff_ST(end)+var2.Boiloff_ET(end))/((var2.mL2(F)+var2.mv2(F))-(var2.mL2(1)+var2.mv2(1)));max(var2.Jtr);
                var2.pv2(F)/100000;var1.p20/100000;var2.hL2(F)/var1.H*100;(var2.mL2(F)+var2.mv2(F));var2.mL2(F);var2.mv2(F);var2.Tv2(F,end);var2.TL2(F,end);
                var2.pv1(F)/100000;var1.p10/100000;var2.hL1(F)/2*var1.R1*100;var2.mL1(F)+var2.mv1(F);var2.mL1(F);var2.mv1(F);var2.Tv1(F,end);var2.TL1(F,end);
                var1.VTotal1*1000;var1.VTotal2*1000;var1.p_ST_fast/100000;var1.p_ET_high/100000;var1.namedetail;TF;var1.ConvCoeffTopfill;var1.TL10];
end

% Write and update
if CM.Scenario == "Trailer to Main"
    writematrix(TopCell,filename,"Sheet","Trailer to Main","Range",NextColLetter+"1",'AutoFitWidth',0);
    writematrix(NewColumn,filename,"Sheet","Trailer to Main","Range",NextColLetter+"2",'AutoFitWidth',0);
    writematrix(ColNumber+1,filename,"Sheet","Trailer to Main","Range","B37",'AutoFitWidth',0);
else
    writematrix(TopCell,filename,"Sheet","Main to On-board","Range",NextColLetter+"1",'AutoFitWidth',0);
    writematrix(NewColumn,filename,"Sheet","Main to On-board","Range",NextColLetter+"2",'AutoFitWidth',0);
    writematrix(ColNumber+1,filename,"Sheet","Main to On-board","Range","B37",'AutoFitWidth',0);
end

end

function A=CaseMethod(Case) % Function to obtain Scenario and Method
if Case==1
    A.Scenario = "Original";
    A.Method = "Pres. diff.";
elseif Case==2
    A.Scenario = "Trailer to Main";
    A.Method = "Pres. diff.";
elseif Case==3
    A.Scenario = "Trailer to Main";
    A.Method = "Pump";
elseif Case==4
    A.Scenario = "Main to On-board";
    A.Method = "Pres. diff.";
else
    A.Scenario = "Main to On-board";
    A.Method = "Pump";
end
end
function TOPBOT=TopBottom(T) % Function to obtain Scenario and Method
if T==1
    TOPBOT = "Top-fill";
else
    TOPBOT = "Bottom-fill";
end
end

function xlcol_addr=num2xlcol(col_num) % Function to convert index number to excel column letter
% col_num - positive integer greater than zero
    n=1;
    while col_num>26*(26^n-1)/25
        n=n+1;
    end
    base_26=zeros(1,n);
    tmp_var=-1+col_num-26*(26^(n-1)-1)/25;
    for k=1:n
        divisor=26^(n-k);
        remainder=mod(tmp_var,divisor);
        base_26(k)=65+(tmp_var-remainder)/divisor;
        tmp_var=remainder;
    end
    xlcol_addr=char(base_26); % Character vector of xlcol address
end
