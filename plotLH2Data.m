function plotLH2Data(data,save,path)
% plotLH2Data(data)
%	Plots results from data.
%	'data' is a data structure returned from LH2Simulate.


% here : T1 or 1 is 17,000 gallon horizontal trailer - feeding vessel 
%        T2 or 2 is 3,300 gallon vertical storage - receiving vessel
%   
set(0, 'DefaultLineLineWidth', 1.7,'DefaultAxesXGrid','on','DefaultAxesYGrid','on','defaultAxesFontSize',12);

try
	P = evalin('base','LH2Model');
    Case = evalin('base','Case');
catch ME
	if strcmp(ME.identifier,'MATLAB:UndefinedFunction')
		evalin('base','LH2ModelParams');
		P = evalin('base','LH2Model');
	else
		error(ME.message);
	end
end

yellow=[0.94 0.80 0.1250];
orange=[0.89 0.5 0.1];
purple=[0.4940 0.1840 0.5560];

TransferredMass=data.EffectiveTransfMass(end)
UsedMass=data.UsedMass(end)
VentingT1=data.Boiloff_ST(end)
VentingT2=data.Boiloff_ET(end)
TotalVenting=data.Boiloff_ST(end)+data.Boiloff_ET(end)
RelativeVenting=TotalVenting/TransferredMass*100   % article Eq. 35: total venting / effectively transferred LH2

%% Figure 1: Liquid levels in T1 and T2 and transfer flow.
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
title('Liquid levels in Tank1 and Tank2 and transfer mass flow.')
subplot(2,2,1);
a=plot(data.t/60,data.hL1/(2*P.R1)*100);
ylabel('Tank 1 Filling height [%]');
xlim([0 data.t(end)/60]);
ylim([0 100]);
xlabel('Time [min]');
legend('T1 level %','Location','southeast');
grid on;

subplot(2,2,2);
b=plot(data.t/60,data.hL2/P.H*100,data.t/60,0.70*100*ones(size(data.t)),data.t/60,0.80*100*ones(size(data.t)),data.t/60,0.90*100*ones(size(data.t)));
b(2).LineWidth = 0.8;
b(3).LineWidth = 0.8;
b(4).LineWidth = 0.8;
b(2).LineStyle="--";
b(3).LineStyle="--";
b(4).LineStyle="--";
b(2).Color = yellow;
b(3).Color = orange;
b(4).Color = purple;
ylabel('Tank 2 Filling height [%]');
xlim([0 data.t(end)/60]);
ylim([0 100]);
xlabel('Time [min]');
legend(' T2 level %','70%','80%','90%','Location','southeast');
grid on;

subplot(2,2,3:4);
c=plot(data.t/60,data.Jtr*60);
ylabel({'Transfer Line Mass Flow';'[kg/min]'});
xlim([0 data.t(end)/60]);
ylim([0 max(data.Jtr)*60+10]);
legend('Mass flow');
xlabel('Time [min]');
grid on;

if save==1
    saveas(gcf,path+"Fig1.png")
    saveas(gcf,path+"Fig1.fig")
end

%% Figure 2: Temperatures.
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
title('Temperatures in Tank1 and Tank2')
subplot(2,2,1:2);
d=plot(data.t/60,data.TL1(:,end),data.t/60,data.Ts1,data.t/60,data.Tv1(:,end));
ylabel('Temperatures in T1 [K]');
xlim([0 data.t(end)/60]);
xlabel('Time [min]');
legend('Liquid','Surface','Vapor','Location','southeast');
grid on;

subplot(2,2,3:4);
e=plot(data.t/60,data.TL2(:,end),data.t/60,data.Ts2,data.t/60,data.Tv2(:,end),data.t/60,data.Tw2);
ylabel('Temperatures in T2 [K]');
xlim([0 data.t(end)/60]);
xlabel('Time [min]');
legend('Liquid','Surface','Vapor','Wall','Location','southeast');
grid on;

if save==1
    saveas(gcf,path+"Fig2.png")
    saveas(gcf,path+"Fig2.fig")
end

%% Figure 3: Pressures and internal energies.
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
title('Internal Energies, Pressures and H2 masses inside of Tank1 and Tank2')
subplot(2,2,1);
f=plot(data.t/60,data.uv1(:,end),data.t/60,data.uL1(:,end),data.t/60,data.uv2(:,end),data.t/60,data.uL2(:,end));
ylabel({'Specific internal energies';'[kJ/kg]'});
xlim([0 data.t(end)/60]);
xlabel('Time [min]');
legend('uv1','uL1','uv2','uL2');
grid on;

subplot(2,2,2);
g=plot(data.t/60,data.pv1/100000,data.t/60,data.pv2/100000,data.t/60,(P.p_ET_high/100000)*ones(size(data.t)),data.t/60,((P.p_ET_low/100000))*ones(size(data.t)));
g(3).LineWidth = 0.8;
g(4).LineWidth = 0.8;
g(3).LineStyle="--";
g(4).LineStyle="--";
ylabel('Pressure [bar]');
xlabel('Time [min]');
legend('Pv1 T1','Pv2 T2','Upper venting press. T2','Lower venting press. T2', 'location', 'south','NumColumns',2);
grid on;
xlim([0 data.t(end)/60]);
ylim([0 max( [max(data.pv1/100000) max(data.pv2/100000) max(P.p_ET_high/100000)] )+0.5]);

subplot(2,2,3);
h=plot(data.t/60,data.mL1,data.t/60,data.mL2);
ylabel('Mass of liquid [kg]');
xlim([0 data.t(end)/60]);
xlabel('Time [min]');
legend('Mass H2 T1','Mass H2 T2','Location','east');
grid on;
xlim([0 data.t(end)/60]);

subplot(2,2,4);
i=plot(data.t/60,data.mv1,data.t/60,data.mVap,data.t/60,data.mv2);
ylabel('Mass of vapor [kg]');
xlim([0 data.t(end)/60]);
xlabel('Time [min]');
legend('T1','vaporizer','T2','Location','east');
grid on;
xlim([0 data.t(end)/60]);
ylim([0 max( [max(data.mv1) max(data.mv2)] )+10]);

if save==1
    saveas(gcf,path+"Fig3.png")
    saveas(gcf,path+"Fig3.fig")
end

%% Figure 4: Densities in storage.
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
title('Vapor and Liquid densities in Tank1 and Tank2 and H2 content in Tank2')
subplot(2,2,1:2);
j=plot(data.t/60,data.rhov1,data.t/60,data.rhov2,data.t/60,data.ETTTVenstate);
ylabel('Vapor densities [g/L]');
legend('T1 vap. dens.','T2 vap. dens.','T2 vent state', 'Location','northwest');
xlim([0 data.t(end)/60]);
xlabel('Time [min]');
grid on;

subplot(2,2,3:4);
k=plot(data.t/60,data.rho_L1,data.t/60,data.rho_L2);
ylabel('Liquid densities (g/L)');
legend('T1 Liq. dens.','T2 Liq. dens.');
xlim([0 data.t(end)/60]);
xlabel('Time [min]');
grid on;

if save==1
    saveas(gcf,path+"Fig4.png")
    saveas(gcf,path+"Fig4.fig")
end

%% Figure 5: Venting flows and stored mass at ST.
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
title('Vented mass and H2 content in T1')
subplot(2,2,1:2);
l=plot(data.t/60,data.Boiloff_ST);
ylabel('Vented mass from T1 [kg])');
xlabel('Time [min]');
legend('T1 Vented mass','Location','southeast');
grid on;
xlim([0 data.t(end)/60]);

subplot(2,2,3:4);
m=plot(data.t/60,data.mL1+data.mv1,data.t/60,data.mL1);
ylabel('Mass in T1 [kg]');
xlim([0 data.t(end)/60]);
ylim([0 max(data.mL1+data.mv1)+10])
xlabel('Time [min]');
legend('T1 Total mass','T1 Liquid mass','Location','southeast');
grid on;

if save==1
    saveas(gcf,path+"Fig5.png")
    saveas(gcf,path+"Fig5.fig")
end

%% Figure 6: Venting flows and stored mass at Tank 2.
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
title('Vented mass and H2 content in Tank 2')
subplot(2,2,1:2);
n=plot(data.t/60,data.Boiloff_ET);
ylabel('Vented mass from T2 [kg]');
xlabel('Time [min]');
legend('T2 Vented mass','Location','southeast');
grid on;
xlim([0 data.t(end)/60]);

subplot(2,2,3:4);
o=plot(data.t/60,data.mL2+data.mv2,data.t/60,data.mL2);
ylabel('Mass in T2 [kg]');
xlim([0 data.t(end)/60]);
ylim([0 max(data.mL2+data.mv2)+10])
legend('T2 Total mass','T2 Liquid mass','Location','southeast');
xlabel('Time [min]');
grid on;

if save==1
    saveas(gcf,path+"Fig6.png")
    saveas(gcf,path+"Fig6.fig")
end

%% Figure 7: Mass flows for vapor phases.
if Case==4 || Case==2
    figure
    set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
    set(gcf,'defaultLineLineWidth',0.8)
    title('Mass flows to vapor phases in Tank1 and Tank2')
    subplot(2,2,1:2);
    p=plot(data.t/60,data.Jv10,data.t/60,-data.Jcd1,data.t/60,-data.Jvvalve1,data.t/60,data.Jboil,data.t/60,data.ZAA);
    p(1).LineWidth = 2;
    ylabel({'Mass flows to VAPOR T1';'[kg/sec] (+ in, - out)'});
    xlim([0 data.t(end)/60]);
    ylim([-0.002 0.001])
    %ylim([-0.008 0.002])
    xlabel('Time [min]');
    legend('TOTAL mf', 'Evaporation mf','(-)Venting mf','Vaporizer mf','Boiling mf');
    grid on;
else
    figure
    set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
    set(gcf,'defaultLineLineWidth',0.8)
    title('Mass flows to vapor phases in Tank1 and Tank2')
    subplot(2,2,1:2);
    p=plot(data.t/60,data.Jv10,data.t/60,-data.Jcd1,data.t/60,-data.Jvvalve1,data.t/60,data.ZAA);
    p(1).LineWidth = 2;
    ylabel({'Mass flows to VAPOR T1';'[kg/sec] (+ in, - out)'});
    xlim([0 data.t(end)/60]);
    ylim([-0.002 0.001])
    %ylim([-0.008 0.002])
    xlabel('Time [min]');
    legend('TOTAL mf', 'Evaporation mf','(-)Venting mf','Boiling mf');
    grid on;
end

subplot(2,2,3:4);
q=plot(data.t/60,data.Jv20,data.t/60,-data.Jcd2,data.t/60,-data.Jvvalve2,data.t/60,data.ZBB,data.t/60,data.JvEvapTopfill);
q(1).LineWidth = 2;
ylabel({'Mass flows to VAPOR T2';'[kg/sec] (+ in, - out)'});
xlim([0 data.t(end)/60]);
ylim([-0.006 0.001])
xlabel('Time [min]');
legend('TOTAL mf', 'Evaporation mf','(-)Venting mf','Boiling mf','Signed top vapor inflow (flash + evap./cond.)');
grid on;

if save==1
    saveas(gcf,path+"Fig7.png")
    saveas(gcf,path+"Fig7.fig")
end

%% Figure 8: Energy balance in T1 
if Case==4 || Case==2
    figure;
    set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
    
    title('Energy balances in Tank 1 and Tank 2')
    subplot(2,1,1);
    r=plot(data.t/60,(P.QdotEV1)*ones(size(data.t))/1000,data.t/60,data.BBB/1000,data.t/60,-data.CCC/1000,data.t/60,data.DDD/1000,data.t/60,data.EEE/1000,data.t/60,data.KKK/1000,data.t/60,data.FFF/1000);
    r(6).LineWidth = 2;
    legend('Environment to vap.','Interphase to vap.','(-)pdV','(-)Venting enth.','Evaporization enth.','TOTAL Heatflow','Vaporizer enth.','Location','south','NumColumns',3)
    ylabel({'Heat flows to VAPOR at T1';'[kW] (+ in, - out)'});
    xlim([0 data.t(end)/60]);
    ylim([-3 .5])
    %ylim([-20 10])
    xlabel('Time [min]');
    grid on;

    subplot(2,1,2);
    s=plot(data.t/60,(P.QdotEL1)*ones(size(data.t))/1000,data.t/60,data.GGG/1000,data.t/60,data.CCC/1000,data.t/60,data.HHH/1000,data.t/60,data.III/1000,data.t/60,data.LLL/1000,data.t/60,data.JJJ/1000);
    s(6).LineWidth = 2;
    legend('Environment to liq.','Interphase to liq.','pdV','LH2 transfer enth.','Condensation enth.','TOTAL Heatflow','(-)Vaporizer enth.','Location','south','NumColumns',3 )
    xlim([0 data.t(end)/60]);
    ylim([-1 4])
    %ylim([-10 20])
    xlabel('Time [min]');
    ylabel({'Heat flows to LIQUID at T1';'[kW](+ in, - out)'});
    grid on;

else
    figure;
    set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
    title('Energy balances in Tank 1 and Tank 2')
    subplot(2,1,1);
    r=plot(data.t/60,(P.QdotEV1)*ones(size(data.t))/1000,data.t/60,data.BBB/1000,data.t/60,-data.CCC/1000,data.t/60,data.DDD/1000,data.t/60,data.EEE/1000,data.t/60,data.KKK/1000);
    r(6).LineWidth = 2;
    legend('Environment to vap.','Interphase to vap.','(-)pdV','(-)Venting enth.','Evaporization enth.','TOTAL Heatflow','Location','south','NumColumns',3)
    ylabel({'Heat flows to VAPOR at T1';'[kW] (+ in, - out)'});
    xlim([0 data.t(end)/60]);
    ylim([-3 .5])
    %ylim([-20 10])
    xlabel('Time [min]');
    grid on;

    subplot(2,1,2);
    s=plot(data.t/60,(P.QdotEL1)*ones(size(data.t))/1000,data.t/60,data.GGG/1000,data.t/60,data.CCC/1000,data.t/60,data.HHH/1000,data.t/60,data.III/1000,data.t/60,data.LLL/1000);
    s(6).LineWidth = 2;
    legend('Environment to liq.','Interphase to liq.','pdV','LH2 transfer enth.','Condensation enth.','TOTAL Heatflow','Location','south','NumColumns',3 )
    xlim([0 data.t(end)/60]);
    ylim([-1 4])
    %ylim([-10 20])
    xlabel('Time [min]');
    ylabel({'Heat flows to LIQUID at T1';'[kW] (+ in, - out)'});
    grid on;
end

%% Figure 8.2: Energy balance in T2
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.

subplot(2,1,1);
t=plot(data.t/60,data.MMM/1000,data.t/60,data.NNN/1000,data.t/60,-data.OOO/1000,data.t/60,data.QQQ/1000,data.t/60,data.RRR/1000,data.t/60,(data.PPP-data.QdotTopfill)/1000,data.t/60,data.WWW/1000);
t(6).LineWidth = 2;
legend('Wall to vapor','Interphase to vap.','(-)pdV','(-)Venting enth.','Evaporation enth.','Signed net top vapor energy','TOTAL Heatflow','Location','south','NumColumns',4 )
ylabel({'Heat flows to VAPOR at T2';'[kW] (+ in, - out)'});
xlim([0 data.t(end)/60]);
ylim([-5 1])
%ylim([-10 10])
xlabel('Time [min]');
grid on;

if ~isfield(data,'YYY')   % run had no pump (pressure-gradient solver); was: if Case==4 || Case==2
    subplot(2,1,2);
    u=plot(data.t/60,data.SSS/1000,data.t/60,data.TTT/1000,data.t/60,data.OOO/1000,data.t/60,data.UUU/1000,data.t/60,data.VVV/1000,data.t/60,data.XXX/1000);
    u(6).LineWidth = 2;
    legend('Wall to liquid','Interphase to liquid','pdV','Bottom + top liquid inlet energy','Condensation enth.','TOTAL Heatflow','Location','south','NumColumns',4 )
    xlim([0 data.t(end)/60]);
    xlabel('Time [min]');
    ylabel({'Heat flows to LIQUID at T2';'[kW] (+ in, - out)'});
    grid on;
else
    subplot(2,1,2);
    u=plot(data.t/60,data.SSS/1000,data.t/60,data.TTT/1000,data.t/60,data.OOO/1000,data.t/60,data.UUU/1000,data.t/60,data.VVV/1000,data.t/60,data.YYY/1000,data.t/60,data.XXX/1000);
    u(6).LineWidth = 2;
    legend('Wall to liquid','Interphase to liquid','pdV','Bottom + top liquid inlet energy','Condensation enth.','Heatflow from pump','TOTAL Heatflow','Location','south','NumColumns',4 )
    xlim([0 data.t(end)/60]);
    xlabel('Time [min]');
    ylabel({'Heat flows to LIQUID at T2';'[kW] (+ in, - out)'});
    grid on;
end 

if save==1
    saveas(gcf,path+"Fig8.png")
    saveas(gcf,path+"Fig8.fig")
end

% %% Figure 9: Zoom pressures with thresholds.
% figure;
% set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.2 0.2 0.6 0.6]); % Enlarge figure to 70% of full screen.
% v=plot(data.t/60,data.pv2/100000,data.t/60,(P.p_ET_high/100000)*ones(size(data.t)),data.t/60,((P.p_ET_low/100000))*ones(size(data.t)));
% v(1).LineWidth = 1.7;
% v(2).LineWidth = 0.8;
% v(3).LineWidth = 0.8;
% v(2).LineStyle="--";
% v(3).LineStyle="--";
% ylabel('Pressure at T2 [bar]');
% xlabel('Time [min]');
% legend('Pv T2','Upper venting press. T2','Lower venting press. T2', 'location', 'south','NumColumns',3);
% grid on;
% xlim([0 data.t(end)/60]);
% ylim([0 max( [max(data.pv1/100000) max(data.pv2/100000) max(P.p_ET_high/100000)] )+0.5]);
% if save==1
%     saveas(gcf,path+"Fig9.png")
%     saveas(gcf,path+"Fig9.fig")
% end
% 
% %% Figure 9.2: Zoom pressures with filled area.
% figure;
% set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.2 0.2 0.6 0.6]); % Enlarge figure to 70% of full screen.
% v=plot(data.t/60,data.pv2/100000);
% v(1).LineWidth = 1.7;
% ylabel('Pressure at T2 [bar]');
% xlabel('Time [min]');
% grid on;
% 
% hold on
% xxx = [0 data.t(end)/60 data.t(end)/60 0];
% yyy = [P.p_ET_low/100000 P.p_ET_low/100000 P.p_ET_high/100000 P.p_ET_high/100000];
% fillcolor1 = [0.85 0.1 0.14];
% fff=fill(xxx,yyy,fillcolor1);
% fff.EdgeColor= 'none';
% fff.FaceAlpha=.25;
% hold off
% xlim([0 data.t(end)/60]);
% ylim([0 max( [max(data.pv1/100000) max(data.pv2/100000) max(P.p_ET_high/100000)] )+0.5]);
% legend('Pv T2','Venting pressure', 'location', 'south','NumColumns',2);
% if save==1
%     saveas(gcf,path+"Fig10.png")
%     saveas(gcf,path+"Fig10.fig")
% end

%% Figure 10: Zoom ET Heat flows.
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.2 0.2 0.6 0.6]); % Enlarge figure to 70% of full screen.
set(gcf,'defaultLineLineWidth',0.8)
w=plot(data.t/60,data.MMM/1000,data.t/60,data.NNN/1000,data.t/60,-data.OOO/1000,data.t/60,data.QQQ/1000,data.t/60,data.RRR/1000,data.t/60,(data.PPP-data.QdotTopfill)/1000,data.t/60,data.WWW/1000);
w(7).LineWidth = 1.7;
legend('Wall to vapor','Interphase to vap.','(-)pdV','(-)Venting enth.','Evaporization enth.','Signed net top vapor energy','TOTAL Heatflow','Location','southoutside','NumColumns',4 )
ylabel({'Heat flows to VAPOR at T2';'[kW] (+ in, - out)'});
xlim([0 data.t(end)/60]);
ylim([-15 5]);
xlabel('Time (min)');
grid on;
if save==1
    saveas(gcf,path+"Fig11.png")
    saveas(gcf,path+"Fig11.fig")
end

%% Figure 11: Zoom ET Mass flows.
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.2 0.2 0.6 0.6]); % Enlarge figure to 70% of full screen.
set(gcf,'defaultLineLineWidth',0.8)
x=plot(data.t/60,data.Jv20,data.t/60,-data.Jcd2,data.t/60,-data.Jvvalve2,data.t/60,data.ZBB,data.t/60,data.JvEvapTopfill);
x(1).LineWidth = 1.7;
ylabel({'Mass flows to VAPOR T2';'[kg/sec] (+ in, - out)'});
xlim([0 data.t(end)/60]);
ylim([-0.003 0.0005]);
xlabel('Time (min)');
legend('TOTAL mf', 'Evaporation mf','(-)Venting mf','Boiling mf', 'Signed top vapor inflow (flash + evap./cond.)');
grid on;

if save==1
    saveas(gcf,path+"Fig12.png")
    saveas(gcf,path+"Fig12.fig")
end

%% Figure 12: pressures T2 psia
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.2 0.2 0.6 0.6]); % Enlarge figure to 70% of full screen.
set(gcf,'defaultLineLineWidth',0.8)
x=plot(data.t/60,data.pv2/100000*14.503773773,data.t/60,(P.p_ET_high/100000*14.503773773+0.001)*ones(size(data.t)),data.t/60,((P.p_ET_low/100000*14.503773773-0.001))*ones(size(data.t)));
x(1).LineWidth = 1.7;
x(2).LineWidth = 0.8;
x(3).LineWidth = 0.8;
x(2).LineStyle="--";
x(3).LineStyle="--";
x(2).Color=[0 .5 0];
x(3).Color=[0 .5 0];
ylabel('Pressure at T2 [psia]');
xlabel('Time [min]');

grid on;
hold on
xxxx = [0 data.t(end)/60 data.t(end)/60 0];
yyyy = [P.p_ET_low/100000*14.503773773 P.p_ET_low/100000*14.503773773 P.p_ET_high/100000*14.503773773 P.p_ET_high/100000*14.503773773];
fillcolor2 = [0.85 0.1 0.14];
ffff=fill(xxxx,yyyy,fillcolor2);
ffff.EdgeColor= 'none';
ffff.FaceAlpha=.3;
hold off

xlim([0 data.t(end)/60]);
ylim([0 max( [max(data.pv1/100000*14.503773773) max(data.pv2/100000*14.503773773) max(P.p_ET_high/100000*14.503773773)] )+0.5]);
legend('Pv2 T2','Venting pressure limits','','Venting region', 'location', 'south','NumColumns',3)

% %% Figure 12: Temperatures with TLevap.
% figure;
% set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
% title('Temperatures in ST and ET')
% subplot(2,2,1:2);
% plot(data.t/60,data.TL1(:,end),data.t/60,data.Ts1,data.t/60,data.Tv1(:,end),data.t/60,data.TL1evap(:,end))
% ylabel('Temperatures in T1 (K)');
% xlim([0 data.t(end)/60]);
% xlabel('Time (min)');
% legend('Liquid','Surface','Vapor','Evaporation');
% grid on;
% 
% subplot(2,2,3:4);
% plot(data.t/60,data.TL2(:,end),data.t/60,data.Ts2,data.t/60,data.Tv2(:,end),data.t/60,data.Tw2,data.t/60,data.TL2evap(:,end))
% ylabel('Temperatures in T2 (K)');
% xlim([0 data.t(end)/60]);
% xlabel('Time (min)');
% legend('Liquid','Surface','Vapor','Twall','Evaporation','Location','southeast','NumColumns',2);
% grid on;
% 
% if save==1
%     saveas(gcf,path+"Fig13.png")
%     saveas(gcf,path+"Fig13.fig")
% end
% 
% %% Figure 13: Temperatures of surface and liquid levels.
% figure;
% set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
% title('Temperatures in the different Liquid volume discretizations in ST and ET')
% subplot(2,2,1:2);
% plot(data.t/60,data.Ts1,data.t/60,data.TL1(:,1),data.t/60,data.TL1(:,2),data.t/60,data.TL1(:,end),data.t/60,data.TL1evap(:,end))
% ylabel('Temperatures in T1 (K)');
% xlim([0 data.t(end)/60]);
% xlabel('Time (min)');
% legend('Surface','Liquid 1','Liquid 2','Liquid end','Evaporation','Location','southeast','NumColumns',2);
% grid on;
% 
% subplot(2,2,3:4);
% plot(data.t/60,data.Ts2,data.t/60,data.TL2(:,1),data.t/60,data.TL2(:,2),data.t/60,data.TL2(:,end),data.t/60,data.TL2evap(:,end))
% ylabel('Temperatures in T2 (K)');
% xlim([0 data.t(end)/60]);
% xlabel('Time (min)');
% legend('Surface','Liquid 1','Liquid 2','Liquid end','Evaporation','Location','southeast','NumColumns',2);
% grid on;
% 
% if save==1
%     saveas(gcf,path+"Fig14.png")
%     saveas(gcf,path+"Fig14.fig")
% end

%% Figure 14: Pressure and Venting T2 with thresholds.
% figure;
% set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
% title('Pressure and Venting mass in Tank2')
% subplot(2,2,1:2);
% aa=plot(data.t/60,data.pv2/100000,data.t/60,(P.p_ET_high/100000)*ones(size(data.t)),data.t/60,((P.p_ET_low/100000))*ones(size(data.t)));
% % aa=plot(data.t/60,data.pv2/100000);
% aa(1).LineWidth = 1.7;
% aa(2).LineWidth = 0.8;
% aa(3).LineWidth = 0.8;
% aa(2).LineStyle="--";
% aa(3).LineStyle="--";
% ylabel('Pressure at T2 [bar]');
% xlabel('Time [min]');
% 
% grid on;
% % hold on
% % xxx = [0 data.t(end)/60 data.t(end)/60 0];
% % yyy = [P.p_ET_low/100000 P.p_ET_low/100000 P.p_ET_high/100000 P.p_ET_high/100000];
% % fillcolor = [0.8500 0.3250 0.0980];
% % fff=fill(xxx,yyy,fillcolor);
% % fff.EdgeColor= 'none';
% % fff.FaceAlpha=.3;
% % hold off
% 
% xlim([0 data.t(end)/60]);
% ylim([0 max( [max(data.pv1/100000) max(data.pv2/100000) max(P.p_ET_high/100000)] )+0.5]);
% legend('Pv2 T2','Upper venting press. T2','Lower venting press. T2', 'location', 'south','NumColumns',3);
% 
% subplot(2,2,3:4);
% bb=plot(data.t/60,data.Boiloff_ET);
% ylabel('Vented mass from T2 [kg]');
% xlabel('Time [min]');
% legend('T2 Vented mass','Location','southeast');
% grid on;
% xlim([0 data.t(end)/60]);
% ylim([0 max(data.Boiloff_ET)+0.5]);
% 
% if save==1
%     saveas(gcf,path+"Fig15.png")
%     saveas(gcf,path+"Fig15.fig")
% end

%% Figure 14: Pressure and Venting T2 with filled area.
% figure;
% set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
% title('Pressure and vented mass in Tank2')
% subplot(2,2,1:2);
% %aa=plot(data.t/60,data.pv2/100000,data.t/60,(P.p_ET_high/100000)*ones(size(data.t)),data.t/60,((P.p_ET_low/100000))*ones(size(data.t)));
% aa=plot(data.t/60,data.pv2/100000);
% aa(1).LineWidth = 1.7;
% %aa(2).LineWidth = 0.8;
% %aa(3).LineWidth = 0.8;
% %aa(2).LineStyle="--";
% %aa(3).LineStyle="--";
% ylabel('Pressure at T2 [bar]');
% xlabel('Time [min]');
% 
% grid on;
% hold on
% xxxx = [0 data.t(end)/60 data.t(end)/60 0];
% yyyy = [P.p_ET_low/100000 P.p_ET_low/100000 P.p_ET_high/100000 P.p_ET_high/100000];
% fillcolor2 = [0.85 0.1 0.14];
% ffff=fill(xxxx,yyyy,fillcolor2);
% ffff.EdgeColor= 'none';
% ffff.FaceAlpha=.3;
% hold off
% 
% xlim([0 data.t(end)/60]);
% ylim([0 max( [max(data.pv1/100000) max(data.pv2/100000) max(P.p_ET_high/100000)] )+0.5]);
% legend('Pv T2','Venting pressure T2', 'location', 'south','NumColumns',2);
% 
% subplot(2,2,3:4);
% bb=plot(data.t/60,data.Boiloff_ET);
% ylabel('Vented mass from T2 [kg]');
% xlabel('Time [min]');
% legend('T2 Vented mass','Location','southeast');
% grid on;
% xlim([0 data.t(end)/60]);
% ylim([0 max(data.Boiloff_ET)+0.5]);
% 
% if save==1
%     saveas(gcf,path+"Fig16.png")
%     saveas(gcf,path+"Fig16.fig")
% end

%% Figure 15: Pressure and Venting T2 with filled area.
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
title('Pressure and Vented mass in Tank2')
subplot(2,2,1:2);
bb=plot(data.t/60,data.pv2/100000,data.t/60,(P.p_ET_high/100000+0.001)*ones(size(data.t)),data.t/60,((P.p_ET_low/100000-0.001))*ones(size(data.t)));
bb(1).LineWidth = 1.7;
bb(2).LineWidth = 0.8;
bb(3).LineWidth = 0.8;
bb(2).LineStyle="--";
bb(3).LineStyle="--";
bb(2).Color=[0 .5 0];
bb(3).Color=[0 .5 0];
ylabel('Pressure at T2 [bar]');
xlabel('Time [min]');

grid on;
hold on
xxxx = [0 data.t(end)/60 data.t(end)/60 0];
yyyy = [P.p_ET_low/100000 P.p_ET_low/100000 P.p_ET_high/100000 P.p_ET_high/100000];
fillcolor2 = [0.85 0.1 0.14];
ffff=fill(xxxx,yyyy,fillcolor2);
ffff.EdgeColor= 'none';
ffff.FaceAlpha=.3;
hold off

xlim([0 data.t(end)/60]);
ylim([0 max( [max(data.pv1/100000) max(data.pv2/100000) max(P.p_ET_high/100000)] )+0.5]);
legend('Pv2 T2','Venting pressure limits','','Venting region', 'location', 'south','NumColumns',3)

subplot(2,2,3:4);
bb=plot(data.t/60,data.Boiloff_ET);
ylabel('Vented mass from T2 [kg]');
xlabel('Time [min]');
legend('T2 Vented mass','Location','southeast');
grid on;
xlim([0 data.t(end)/60]);
ylim([0 max(data.Boiloff_ET)+0.5]);

if save==1
    saveas(gcf,path+"Fig17.png")
    saveas(gcf,path+"Fig17.fig")
end

%% Figure 16: Figure 1 + Figure 15 RELATIVE Venting
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.15 0.7 0.7]); % Enlarge figure to 70% of full screen.
%title('Liquid levels in Tank1 and Tank2 and transfer mass flow.')

subplot(2,2,1);
b=plot(data.t/60,data.hL1/(2*P.R1)*100,data.t/60,data.hL2/P.H*100,data.t/60,0.70*100*ones(size(data.t)),data.t/60,0.80*100*ones(size(data.t)),data.t/60,0.90*100*ones(size(data.t)));
b(3).LineWidth = 0.8;
b(4).LineWidth = 0.8;
b(5).LineWidth = 0.8;
b(3).LineStyle="--";
b(4).LineStyle="--";
b(5).LineStyle="--";
b(3).Color = yellow;
b(4).Color = orange;
b(5).Color = purple;
ylabel('Tank Filling height [%]');
xlim([0 data.t(end)/60]);
% xlim([0 4.5]);
ylim([0 100]);
xlabel('Time [min]');
legend('T1 level %','T2 level %','70%','80%','90%','Location','southeast');
grid on;
yticks(0:20:100)
%xticks(0:.5:8)

subplot(2,2,2);
bb=plot(data.t/60,data.pv1/100000,data.t/60,data.pv2/100000,data.t/60,(P.p_ET_high/100000+0.001)*ones(size(data.t)),data.t/60,((P.p_ET_low/100000-0.001))*ones(size(data.t)));
bb(1).LineWidth = 1.7;
bb(2).LineWidth = 1.7;
bb(3).LineWidth = 0.8;
bb(4).LineWidth = 0.8;
bb(3).LineStyle="--";
bb(4).LineStyle="--";
bb(3).Color=[0 .5 0];
bb(4).Color=[0 .5 0];
ylabel('Pressures [bar]');
xlabel('Time [min]');
grid on;
yticks(0:2:12)
%xticks(0:.5:8)
hold on
xxxx = [0 data.t(end)/60 data.t(end)/60 0];
yyyy = [P.p_ET_low/100000 P.p_ET_low/100000 P.p_ET_high/100000 P.p_ET_high/100000];
fillcolor2 = [0.85 0.1 0.14];
ffff=fill(xxxx,yyyy,fillcolor2);
ffff.EdgeColor= 'none';
ffff.FaceAlpha=.3;
hold off
xlim([0 data.t(end)/60]);
% xlim([0 4.5]);
ylim([0 max( [max(data.pv1/100000) max(data.pv2/100000) max(P.p_ET_high/100000)] )+0.5]);
legend('Pressure T1','Pressure T2','Venting pressure limits','','Venting region', 'location', 'south','NumColumns',3)

subplot(2,2,3);
c=plot(data.t/60,data.Jtr*60);
ylabel({'Transfer Line Mass Flow';'[kg/min]'});
xlim([0 data.t(end)/60]);
% xlim([0 4.5]);
ylim([0 max(data.Jtr)*60+5]);
legend('Mass flow');
xlabel('Time [min]');
grid on;
%xticks(0:.5:8)

subplot(2,2,4);
dd=plot(data.t/60,data.Boiloff_ET/TransferredMass*100);
dd(1).Color=[0.8500 0.3250 0.0980];
ylabel('Relative Venting [%]');
xlabel('Time [min]');
legend('Relative Venting T2','Location','northwest');
grid on;
xlim([0 data.t(end)/60]);
% xlim([0 4.5]);
ylim([0 max(data.Boiloff_ET/TransferredMass*100)+0.5]);
yticks(0:1:25)
%xticks(0:.5:8)

if save==1
    saveas(gcf,path+"Fig18.png")
    saveas(gcf,path+"Fig18.fig")
end

%% Figure 17: Transferred mass, effective transferred mass & Venting
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.15 0.1 0.7 0.8]); % Enlarge figure to 70% of full screen.
%title('Liquid levels in Tank1 and Tank2 and transfer mass flow.')

subplot(2,1,1);
b=plot(data.t/60,data.UsedMass,data.t/60,data.EffectiveTransfMass,data.t/60,data.Boiloff_ST,data.t/60,data.Boiloff_ET);
ylabel('Mass [kg]');
xlim([0 data.t(end)/60]);
% ylim([0 max(data.AccTransfMass)+100]);
ylim([0 UsedMass+20]);
xlabel('Time [min]');
legend('Used mass','Effectively transferred mass','Vented mass T1','Vented mass T2','Location','northwest');
grid on;
% yticks(0:20:160)
%xticks(0:.5:8)

subplot(2,1,2);
dd=plot(data.t/60,data.Boiloff_ST/UsedMass*100,data.t/60,data.Boiloff_ET/UsedMass*100,data.t/60,(data.Boiloff_ET+data.Boiloff_ST)/UsedMass*100);
ylabel('Relative Venting [%]');
xlabel('Time [min]');
legend('Relative Venting T1','Relative Venting T2','Total relative Venting','Location','northwest');
grid on;
xlim([0 data.t(end)/60]);
% xlim([0 4.5]);
ylim([0 max((data.Boiloff_ET+data.Boiloff_ST)/UsedMass*100)+0.5]);
yticks(0:1:15)
%xticks(0:.5:8)

if save==1
    saveas(gcf,path+"Fig19.png")
    saveas(gcf,path+"Fig19.fig")
end

%% Figure 17: Process ending flags
figure;
gg=plot(data.t/60,data.ProcComp,data.t/60,data.ETFilled,data.t/60,data.ETVentComp,data.t/60,data.STVentComp);
ylabel('Flags 0-1');
xlabel('Time [min]');
legend('Process complete','ET Fill complete','ET Vent complete','ST Vent complete','Location','northwest');
grid on;
xlim([0 data.t(end)/60]);
% xlim([0 4.5]);
ylim([0 1.05]);

%%
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.2 0.2 0.6 0.6]); % Enlarge figure to 70% of full screen.
if isfield(data,'YYY')   % pump-only figures (Figs. 20-21); pressure-gradient runs have no pump
plot(data.t/60,data.YYY/1000)
ylabel('Inefficiencies at pump [kW]');
xlabel('Time [min]');
legend('Pump','Location','northwest');
grid on;
xlim([0 data.t(end)/60]);
if save==1
    saveas(gcf,path+"Fig20.png")
    saveas(gcf,path+"Fig20.fig")
end

%%
for i = 1:length(data.t)
LH2TinT2(i)=refpropm('T','P',data.pv2(i)/1000,'H',data.hAfterPump(i),'PARAHYD');
end
figure;
set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.2 0.2 0.6 0.6]); % Enlarge figure to 70% of full screen.
plot(data.t/60,data.TL1(:,end),data.t/60,LH2TinT2)
ylabel('Temperature [K]');
xlabel('Time [min]');
legend('Pump inlet','Pump outlet','Location','northwest');
grid on;
xlim([0 data.t(end)/60]);
if save==1
    saveas(gcf,path+"Fig21.png")
    saveas(gcf,path+"Fig21.fig")
end
end 