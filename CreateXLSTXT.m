function CreateXLSTXT(var1,var2,path,dateandtime,Case)

% Creating filename
filenamexls=path+"MainResults_"+dateandtime+"_"+var1.name+".xls";
filenametxt=path+"MainResults_"+dateandtime+"_"+var1.name+".txt";

% Obtaining Scenario and Method
CM=CaseMethod(Case);

% Finding the index for when the process is considered finished.
if isempty(find(var2.ProcComp,1,'first'))
    F=size(var2.t,1); % If the flag for the process completed was not created, we take the last element
else
    F=round(find(var2.ProcComp,1,'first')*1.1); % We multiply the index by a factor of 1.1 to make sure the process has finished
    if F>size(var2.t,1)
        F=round(find(var2.ProcComp,1,'first')*1.05); % If F*1.1 exceeds index, we multiply the index by a factor of 1.05 to make sure the process has finished
        if F>size(var2.t,1)
            F=round(find(var2.ProcComp,1,'first')*1); % If F*1.05 exceeds index, we take F as it is.
        end
    end
end

% Creating vectors and table 
Parameter = ["Date";"Case";"Method";"Duration";"Transferred H2";"Boil-off ST";"Boil-off ET";"Total boil-off";"Relative boil-off";"Max. transfer rate";
    "ET final pressure";"ET initial pressure";"ET height";"ET total mass";"ET liquid mass";"ET vapor mass";"ET vapor temp.";"ET liquid temp.";
    "ST final pressure";"ST initial pressure";"ST height";"ST total mass";"ST liquid mass";"ST vapor mass";"ST vapor temp.";"ST liquid temp.";
    "ST volume";"ET volume";"ST rated pressure";"ET rated pressure";"Name"];

if CM.Method=="Pump"
    FinalValue = [dateandtime;CM.Scenario;CM.Method;var2.t(F);(var2.mL2(F)+var2.mv2(F))-(var2.mL2(1)+var2.mv2(1));var2.Boiloff_ST(end);var2.Boiloff_ET(end);var2.Boiloff_ST(end)+var2.Boiloff_ET(end);(var2.Boiloff_ST(end)+var2.Boiloff_ET(end))/((var2.mL2(F)+var2.mv2(F))-(var2.mL2(1)+var2.mv2(1)));max(var2.Jtr);
                  var2.pv2(F)/100000;var1.p20/100000;var2.hL2(F)/var1.H*100;(var2.mL2(F)+var2.mv2(F));var2.mL2(F);var2.mv2(F);var2.Tv2(F,end);var2.TL2(F,end);
                  var2.pv1(F)/100000;var1.p10/100000;var2.hL1(F)/2*var1.R1*100;var2.mL1(F)+var2.mv1(F);var2.mL1(F);var2.mv1(F);var2.Tv1(F,end);var2.TL1(F,end);
                  var1.VTotal1*1000;var1.VTotal2*1000;var1.p_ST_high/100000;var1.p_ET_high/100000;var1.namedetail];
else
    FinalValue = [dateandtime;CM.Scenario;CM.Method;var2.t(F);(var2.mL2(F)+var2.mv2(F))-(var2.mL2(1)+var2.mv2(1));var2.Boiloff_ST(end);var2.Boiloff_ET(end);var2.Boiloff_ST(end)+var2.Boiloff_ET(end);(var2.Boiloff_ST(end)+var2.Boiloff_ET(end))/((var2.mL2(F)+var2.mv2(F))-(var2.mL2(1)+var2.mv2(1)));max(var2.Jtr);
                  var2.pv2(F)/100000;var1.p20/100000;var2.hL2(F)/var1.H*100;(var2.mL2(F)+var2.mv2(F));var2.mL2(F);var2.mv2(F);var2.Tv2(F,end);var2.TL2(F,end);
                  var2.pv1(F)/100000;var1.p10/100000;var2.hL1(F)/2*var1.R1*100;var2.mL1(F)+var2.mv1(F);var2.mL1(F);var2.mv1(F);var2.Tv1(F,end);var2.TL1(F,end);
                  var1.VTotal1*1000;var1.VTotal2*1000;var1.p_ST_fast/100000;var1.p_ET_high/100000;var1.namedetail];
end

Units = [" ";" ";" ";"s";"kg";"kg";"kg";"kg";"kg boiloff/kg transferred";"kg/s";
    "bar";"bar";"%";"kg";"kg";"kg";"K";"K";
    "bar";"bar";"%";"kg";"kg";"kg";"K";"K";
    "liters";"liters";"bar";"bar";" "];

% Append top-fill settings when available, preserving all existing entries.
if all(isfield(var1, {'TF_mode', 'TF_r', 'TF_D_d'}))
    Parameter = [Parameter; "TF_mode"; "TF_r"; "TF_D_d"];
    FinalValue = [FinalValue; string(var1.TF_mode); var1.TF_r; var1.TF_D_d];
    Units = [Units; " "; " "; "m"];
end

ResultsTable=table(Parameter,FinalValue,Units);

% Saving table to .txt file
writetable(ResultsTable,filenamexls)
writetable(ResultsTable,filenametxt)

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
