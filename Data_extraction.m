% here : (ST) or 1 is trailer (horizontal cylinder)
%        (ET) or 2 is station storage (vertical cylinder)    

LH2Model = evalin('base','LH2Model');
 % z=1:fix(length(Simulation.t)*0.05)
    Simulation.rho_L1 = -5.12074746E-07*((Simulation.uL1(:,LH2Model.nL1))./1000).^3 - 1.56628367E-05*((Simulation.uL1(:,LH2Model.nL1))./1000).^2 - 1.18436797E-01*((Simulation.uL1(:,LH2Model.nL1))./1000) + 7.06218354E+01;
    Simulation.VL1 = Simulation.mL1./Simulation.rho_L1;
    Simulation.Vullage1 = LH2Model.VTotal1-Simulation.VL1;
    Simulation.rhov1 = Simulation.mv1./Simulation.Vullage1;
    
    Simulation.rho_L2 = -5.12074746E-07*((Simulation.uL2(:,LH2Model.nL2))./1000).^3 - 1.56628367E-05*((Simulation.uL2(:,LH2Model.nL2))./1000).^2 - 1.18436797E-01*((Simulation.uL2(:,LH2Model.nL2))./1000) + 7.06218354E+01; % correlation from REFPROP v9.1
    Simulation.VL2 = Simulation.mL2./Simulation.rho_L2;
    Simulation.Vullage2= LH2Model.VTotal2-Simulation.VL2;
    Simulation.rhov2 = Simulation.mv2./Simulation.Vullage2;
    Simulation.pcthL2 = Simulation.hL2./LH2Model.H;

    % Simulation.VL1(z) = LH2Model.A1./Simulation.hL1(z);
    % Simulation.rho_L1(z) = Simulation.mL1(z)/Simulation.VL1(z);
    % Simulation.Vullage1(z) = LH2Model.VTotal1-Simulation.VL1(z);
    % Simulation.rhov1(z) = Simulation.mv1(z)./Simulation.Vullage1(z);
    % 
    % Simulation.VL2(z) = LH2Model.A2./Simulation.hL2(z);
    % Simulation.rho_L2(z) = Simulation.mL2(z)/Simulation.VL2(z);
    % Simulation.Vullage2(z) = LH2Model.VTotal2-Simulation.VL2(z);
    % Simulation.rhov2(z) = Simulation.mv2(z)./Simulation.Vullage2(z);
    % Simulation.pcthL2(z) = Simulation.hL2(z)./LH2Model.H;

% Creation of waitbar
% h = waitbartime(0,'Data is being extracted. Please wait...');
h = waitbar(0,'Extracting data. Please wait...'); % Simpler waitbar, without time estimation
clear Simulation.rho_L2
for z=1:length(Simulation.rhov1)
    
        Simulation.pv1(z,:)=vaporpressure(Simulation.uv1(z,end), Simulation.rhov1(z));
        Simulation.TL1evap(z,1) = refpropm('T','P',Simulation.pv1(z)/1000,'Q',0,'PARAHYD');
        for ii = 1:LH2Model.nV1
            if Simulation.uv1(z,ii)<0*(-108.8/(2.0159/1000))
                Simulation.uv1(z,ii)= 0;
            end

            Simulation.Tv1(z,ii) = refpropm('T','P',Simulation.pv1(z)/1000,'U',Simulation.uv1(z,ii),'PARAHYD');
        end
        for ii = 1:LH2Model.nL1
            % Simulation.TL1(z,ii) = -0.0002041552*(Simulation.uL1(z,ii)/1000)^2 + 0.1010598604*Simulation.uL1(z,ii)/1000 + 20.3899281428; %rho_L2 = -1.247729862408E-05*(TL2(LH2Model.nL2))^6 + 1.6810
            Simulation.TL1(z,ii)=refpropm('T','P',(Simulation.pv1(z)+1)/1000,'U',Simulation.uL1(z,ii),'PARAHYD');
            
        end
        %Simulation.Jvalve111(z,:)=gasFlow(LH2Model.S_valve1,LH2Model.gamma_,Simulation.rhov1(z),Simulation.pv1(z),LH2Model.p_atm);%*(Simulation.pv1(z)>LH2Model.p_ST_final);
        %Simulation.hL1(z) = cylVToH(Simulation.VL1(z),LH2Model.R1,LH2Model.Lcyl);
  
       
        Simulation.pv2(z,:)=vaporpressure(Simulation.uv2(z,end),Simulation.rhov2(z));
        %Simulation.TL2evap(z,1) = refpropm('T','P',Simulation.pv2(z)/1000,'Q',0,'PARAHYD');
        %Simulation.Jvalve222(z,:)=Simulation.ETTTVenstate(z)*gasFlow(LH2Model.S_valve2,LH2Model.gamma_,Simulation.rhov2(z),Simulation.pv2(z),LH2Model.p_atm);
        for ii = 1:LH2Model.nV2
            if Simulation.uv2(z,ii)<0*(-108.8/(2.0159/1000))
                Simulation.uv2(z,ii)= 0;
            end
            Simulation.Tv2(z,ii) = refpropm('T','P',Simulation.pv2(z)/1000,'U',Simulation.uv2(z,ii),'PARAHYD');
        end
        for ii = 1:LH2Model.nL2
            % Simulation.TL2(z,ii) = -0.0002041552*(Simulation.uL2(z,ii)/1000)^2 + 0.1010598604*Simulation.uL2(z,ii)/1000 + 20.3899281428; %rho_L2 = -1.247729862408E-05*(TL2(LH2Model.nL2))^6 + 1.6810
            Simulation.TL2(z,ii) = refpropm('T','P',(Simulation.pv2(z)+1)/1000,'U',Simulation.uL2(z,ii),'PARAHYD');
        end
        
        Simulation.rho_L2(z) = refpropm('D','P',(Simulation.pv2(z)+1)/1000,'U',Simulation.uL2(z,ii),'PARAHYD');
        Simulation.Jv10(z) = Simulation.Jboil(z) -Simulation.Jvvalve1(z) - Simulation.Jcd1(z) + Simulation.ZAA(z);
        Simulation.Jv20(z) = -Simulation.Jvvalve2(z) - Simulation.Jcd2(z) + Simulation.ZBB(z) + Simulation.JvEvapTopfill(z); % Filtered signed top vapor inflow (ZKK).
        
        % waitbartime(z/length(Simulation.rhov1),h);
        waitbar(z/length(Simulation.rhov1),h,sprintf('Extracting data. please wait... %2.2f%%',(z/length(Simulation.rhov1)*100))) % Simpler waitbar, without time estimation

end
    
close(h) % close waitbar 
    
    %Simulation.pL1 = Simulation.rho_L1.*LH2Model.g.*(Simulation.hL1)';
    Simulation.pL1 = Simulation.rho_L1.*LH2Model.g.*(Simulation.hL1);
    Simulation.pTotal1 = Simulation.pv1+Simulation.pL1;
    Simulation.S1 = pi*(LH2Model.R1^2-(LH2Model.R1 - Simulation.hL1).^2);
      
    Simulation.pL2 = Simulation.rho_L2.*LH2Model.g.*(Simulation.hL2);
    Simulation.pTotal2 = Simulation.pv2+Simulation.pL2;
    
    Simulation.Boiloff_ST=zeros(length(Simulation.t),1);
    Simulation.Boiloff_ET=zeros(length(Simulation.t),1);
    Simulation.AccTransfMass=zeros(length(Simulation.t),1);
    Simulation.AccEffectiveTransfMass=zeros(length(Simulation.t),1);
    for ii = 2:length(Simulation.t)
        Simulation.Boiloff_ST(ii) = Simulation.Boiloff_ST(ii-1) + (Simulation.t(ii)-Simulation.t(ii-1))* Simulation.Jvvalve1(ii);
        Simulation.Boiloff_ET(ii) = Simulation.Boiloff_ET(ii-1) + (Simulation.t(ii)-Simulation.t(ii-1))* Simulation.Jvvalve2(ii);
        Simulation.AccTransfMass(ii) = Simulation.AccTransfMass(ii-1) + (Simulation.t(ii)-Simulation.t(ii-1))* Simulation.Jtr(ii);
        Simulation.EffectiveTransfMass(ii) = Simulation.AccTransfMass(ii) - Simulation.Boiloff_ET(ii);
        Simulation.UsedMass(ii) = Simulation.AccTransfMass(ii) + Simulation.Boiloff_ST(ii);

    end
    
    Simulation.Jv10 = Simulation.Jboil -Simulation.Jvvalve1 - Simulation.Jcd1 + Simulation.ZAA;
    Simulation.Jv20 = -Simulation.Jvvalve2 - Simulation.Jcd2 + Simulation.ZBB + Simulation.JvEvapTopfill; % All diagnostic rates are first-order filtered.
    disp('Data extraction done');
    
    
    
    
    
