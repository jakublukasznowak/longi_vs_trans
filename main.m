
% Select plane: ATR, C130 or TO

plane = 'TO';


% Prepare paths

projectpath = pwd;

addpath(genpath(projectpath))

datapath = [mydatapath,filesep,plane];

plotpath = [projectpath,filesep,'figures'];
if ~isfolder(plotpath)
    mkdir(plotpath)
end


% MYDATAPATH is the path where you downloaded the datasets:
%
% MYDATAPATH/ATR/TURBLENCE
%
% Lothon, M. & Brilouet, P. (2020). SAFIRE ATR42: Turbulence Data 25 Hz. Aeris.
% doi.org/10.25326/128
% https://observations.ipsl.fr/aeris/eurec4a-data/AIRCRAFT/ATR/SAFIRE-TURB/PROCESSED/
% 
% In this code 'longlegs' L3 v1.9 is used.
%
%
% MYDATAPATH/C130/TURBULENCE
% 
% NCAR/NSF C-130 Navigation, State Parameter, and Microphysics HRT (25 sps) Data
% doi.org/10.5065/D69K48JK
% https://data.eol.ucar.edu/dataset/89.002
%
% MYDATAPATH/C130/LIDAR
% 
% NSF/NCAR C130 Radar, Lidar and Radiometer Integrated Dataset
% doi.org/10.26023/8KEJ-BQNG-W808 
% https://data.eol.ucar.edu/dataset/89.159
%
%
% MYDATAPATH/TO/TURBULENCE
%
% UC Irvine 40-hz Probes - netCDF format
% doi.org/10.26023/KP56-KFJS-VC07 
% https://data.eol.ucar.edu/dataset/111.033
%
% MYDATAPATH/TO/cloud_tops.txt
%
% Table 1 from Carman, J. K., Rossiter, D. L., Khelif, D., Jonsson, H. H.,
% Faloona, I. C., and Chuang, P. Y.: Observational constraints on entrainment
% and the entrainment interface layer in stratocumulus, Atmos. Chem. Phys.,
% 12, 11135–11152, https://doi.org/10.5194/acp-12-11135-2012, 2012. 
% (as tab-delimited text file).



%% Load datasets


if strcmp(plane,'ATR')
    
    fit_range = [16 80];
    
    % List of levels
    levels  = {'cloud-base','top-subcloud','mid-subcloud','near-surface'};

    % List of flights
    flight_ids = num2cell(num2str((9:19)','RF%02d'),2); % RF09 - RF19

    % List of variables from turbulent moments dataset
    mom_vars = {'alt','MEAN_WSPD','MEAN_WDIR','MEAN_TAS','MEAN_THDG'};

    % List of variables from turbulent fluctuations dataset
    turb_vars = {'W','W_DET';
                 'UX','UX_DET';
                 'VY','VY_DET'};


    % Read data files

    SEG = load_atr_seg(datapath,'v1.9','longlegs');                          % Flight segmentation
    [MOM,mom_info] = load_atr_mom(datapath,'L3','v1.9','longlegs',mom_vars); % Mean values and moments
    
    SEG = SEG(ismember(SEG.flight,flight_ids) & ismember(SEG.level,levels),:); % Select segments
    MOM = join(SEG,MOM,'Keys',{'start','end'});

    TURB = load_atr_turb(MOM,datapath,'L3','v1.9',turb_vars(:,2),turb_vars(:,1)); % Load signals for the selected segments only

    
elseif strcmp(plane,'C130')
    
    fit_range = [16 80];
    
    % List of levels
    levels  = {'in-cloud','cloud-base','sub-cloud'};
    
    % List of variables from turbulence dataset
    turb_vars = {'time','Time';
                 'ALT','ALTX';
                 'TAS','TASX';
                 'THDG','THDG';
                 'U','UIC';
                 'V','VIC';
                 'W','WIC';
                 'UX','UXC';
                 'VY','VYC'};
    
             
    % Read data files
    
    [DATA,turb_info] = read_turb([datapath,filesep,'TURBULENCE'],turb_vars(:,2),turb_vars(:,1));
    [SEG,seg_info] = load_c130_seg(datapath); % Segmentation from auxiliary dataset
    
    
    % Process
    
    SEG = SEG(ismember(SEG.level,levels),:); % Select segments
    TURB = calc_turb(SEG,DATA);              % Cut signals to the segments
    MOM = calc_mom(TURB);                    % Calculate mean segment values

    
elseif strcmp(plane,'TO')
    
    fit_range = [8 80];
    
    % List of levels
    levels  = {'cloud-top','cloud-base','sub-cloud'};%,'near-surface'};
    
    % List of variables from turbulence dataset
    turb_vars = {'time','Time';
                 'ALT','RADALT';
                 'TAS','TAS';
                 'THDG','GTRK'; 
                 'U','WX';
                 'V','WY';
                 'W','WZ'};
   
    
    % Read data files
    
    [DATA,turb_info] = read_turb([datapath,filesep,'TURBULENCE'],turb_vars(:,2),turb_vars(:,1));
    CT = readtable([datapath,filesep,'cloud_tops.txt']);
    
    
    % Process
    
    SEG = calc_seg(DATA,true);  % Algorithmic detection of horizontal segments
    TURB = calc_turb(SEG,DATA); % Cut signals to the segments
    TURB = uv2uxvy(TURB);       % Wind rotation from U,V to UX,VY
    MOM = calc_mom(TURB);       % Calculate mean segment values
    
    % Append cloud heights to MOM
    for i_s = 1:size(MOM,1)
        ind_f = find(strcmp(CT.flight,MOM.flight(i_s)));
        MOM.cloud_base(i_s) = CT.cloud_base(ind_f);
        MOM.cloud_top(i_s)  = CT.cloud_top(ind_f);
        MOM.cloud_top_std(i_s) = CT.cloud_top_std(ind_f);
    end
    MOM.cloud_mid = mean([MOM.cloud_base MOM.cloud_top],2);
    
    % Classify segments according to height 
    MOM.level = repmat("",size(MOM,1),1);
    MOM.level(MOM.alt<60) = "near-surface";
    MOM.level(MOM.alt>=60 & MOM.alt<MOM.cloud_base) = "sub-cloud";
    MOM.level(MOM.alt>=MOM.cloud_base & MOM.alt<MOM.cloud_mid) = "cloud-base";
    MOM.level(MOM.alt>=MOM.cloud_mid & MOM.alt<MOM.cloud_top+MOM.cloud_top_std) = "cloud-top";
    MOM.level(MOM.alt>=MOM.cloud_top+MOM.cloud_top_std) = "free-troposphere";
    MOM = movevars(MOM,{'flight','level','alt','length',...
        'cloud_base','cloud_top','cloud_top_std'},'Before',1);
    
    % Select segments
    ind_s = ismember(MOM.level,levels) & MOM.length>=20e3;
    TURB = TURB(ind_s,:);
    MOM  = MOM(ind_s,:);

end

MOM.dr = MOM.MEAN_TAS./[TURB.fsamp]';

clear SEG DATA


% Plot overview of the segments

plot_seg_overview(MOM,levels);
title(plane)



%% Calculate dissipation

% Constants

B_L = 2.0; B_T = 2.6;
C_L = 0.5; C_T = 0.66;


% Settings

sfc_method = "logmean";
sfc_fit_points = 6;

psd_method = "logmean";
psd_fit_points = 6;
psd_win_length = 1000; % m
psd_win_overlap = 500; % m

vars = {'W','UX','VY'};
B = [B_T B_L B_T];
C = [C_T C_L C_T];


% Compute

disp('Compute dissipation rate ...')

Nvar = numel(vars);
Nseg = size(MOM,1);
E = struct([]);

for i_v = 1:Nvar
    var = vars{i_v}; fprintf('%2s',var)
    
    for i_s = 1:Nseg
        fprintf(' %d',i_s)
        dr = MOM.dr(i_s);

        [MOM.(['edr_sfc_',var])(i_s),MOM.(['slp_sfc_',var])(i_s),es] = edr_sfc( detrend(TURB(i_s).(var)),...
            dr,fit_range,B(i_v),'Method',sfc_method,'FitPoints',sfc_fit_points );
        
        [MOM.(['edr_psd_',var])(i_s),MOM.(['slp_psd_',var])(i_s),ep] = edr_psd( detrend(TURB(i_s).(var)),...
            dr,fit_range,C(i_v),'Method',psd_method,'FitPoints',psd_fit_points,...
            'WindowLength',floor(psd_win_length/dr),'WindowOverlap',floor(psd_win_overlap/dr) );
        
        E(1).(['sfc_',var])(i_s) = es;
        E(1).(['psd_',var])(i_s) = es;
    end
    
    E.(['sfc_',var]) = struct2table(E.(['sfc_',var]));
    E.(['psd_',var]) = struct2table(E.(['psd_',var]));
    
    fprintf('\n')
end


% Dependent parameters

% sfc and psd prefactors
for i_v = 1:Nvar
    var = vars{i_v};
    
    MOM.(['off_sfc_',var]) = B(i_v)*MOM.(['edr_sfc_',var]).^(2/3);
    MOM.(['off_psd_',var]) = C(i_v)*MOM.(['edr_psd_',var]).^(2/3);
    
    E.(['sfc_',var]).off = MOM.(['off_sfc_',var]) .* E.(['sfc_',var]).offsetFixed;
end

% Anisotropy
MOM.ar_sfc_WU = MOM.off_sfc_W./MOM.off_sfc_UX;
MOM.ar_sfc_WV = MOM.off_sfc_W./MOM.off_sfc_VY;
MOM.ar_psd_WU = MOM.off_psd_W./MOM.off_psd_UX;
MOM.ar_psd_WV = MOM.off_psd_W./MOM.off_psd_VY;

% Dissipation rates after reversal of longi/trans
MOM.edr_sfc_UY = MOM.edr_sfc_UX * (B_L/B_T).^(3/2);
MOM.edr_sfc_VX = MOM.edr_sfc_VY * (B_T/B_L).^(3/2);
MOM.edr_psd_UY = MOM.edr_psd_UX * (C_L/C_T).^(3/2);
MOM.edr_psd_VX = MOM.edr_psd_VY * (C_T/C_L).^(3/2);



%% Integral length scale

disp('Compute integral length scale ...')

for i_v = 1:Nvar
    var = vars{i_v}; fprintf('%2s',var)
    for i_s = 1:Nseg
        fprintf(' %d',i_s)
        MOM.(['ls_',var])(i_s) = int_ls_short(detrend(TURB(i_s).(var)))*MOM.dr(i_s);
    end
    fprintf('\n')
end



%% Summmary of segments

sortrows(groupsummary(MOM,"level",["mean","std","min","max"],...
    ["alt","ls_W","length"]),"mean_alt",'descend')



%% PLOTS

dirs = {'along','cross'};


%% Examples of dissipation rate derivation

ex_s = 32;

i_s = ex_s;
dr = MOM.dr(i_s);

for i_v = 1:Nvar
    var = vars{i_v};
    
    edr_sfc( detrend(TURB(i_s).(var)), dr,fit_range,B(i_v),'Method',sfc_method,...
        'FitPoints',sfc_fit_points,'Plot',true,'PlotRange',[dr 1000] );
    
    title(join([plane,MOM.flight(i_s),round(MOM.alt(i_s)),'m',var]))
    print(gcf,join([[plotpath,filesep,'ex'],plane,'sfc',var,string(i_s)],'_'),'-dpng','-r300')
end

for i_v = 1:Nvar
    var = vars{i_v};
    
    edr_psd( detrend(TURB(i_s).(var)), dr,fit_range,C(i_v),'Method',psd_method,...
        'FitPoints',psd_fit_points,'Plot',true,'PlotRange',[2*dr 1000],...
        'WindowLength',floor(psd_win_length/dr),'WindowOverlap',floor(psd_win_overlap/dr) );
    
    title(join([plane,MOM.flight(i_s),round(MOM.alt(i_s)),'m',var]))
    print(gcf,join([[plotpath,filesep,'ex'],plane,'psd',var,string(i_s)],'_'),'-dpng','-r300')
end


%% (u,v)^2/3

fig = plot_xy(MOM,{'off_sfc_UX'},{'off_sfc_VY'},levels,'levels',1,1,{'cross3/4','cross1','cross4/3'});
legend(cat(2,levels,dirs),'Location','northwest')
xlabel('$B_L\epsilon_u^{2/3}\,\textrm{sfc}$','Interpreter','latex')
ylabel('$B_T\epsilon_v^{2/3}\,\textrm{sfc}$','Interpreter','latex')
title(plane)
print(fig,[plotpath,filesep,'uv23_',plane,'_sfc'],'-dpng','-r300')

fig = plot_xy(MOM,{'off_psd_UX'},{'off_psd_VY'},levels,'levels',1,1,{'cross3/4','cross1','cross4/3'});
legend(cat(2,levels,dirs),'Location','northwest')
xlabel('$C_L\epsilon_u^{2/3}\,\textrm{psd}$','Interpreter','latex')
ylabel('$C_T\epsilon_v^{2/3}\,\textrm{psd}$','Interpreter','latex')
title(plane)
print(fig,[plotpath,filesep,'uv23_',plane,'_psd'],'-dpng','-r300')


%% (u,w)^2/3

fig = plot_xy(MOM,{'off_sfc_UX'},{'off_sfc_W'},levels,'levels',1,1,{'cross3/4','cross1','cross4/3'});
legend(cat(2,levels,dirs),'Location','northwest')
xlabel('$B_L\epsilon_u^{2/3}\,\textrm{sfc}$','Interpreter','latex')
ylabel('$B_T\epsilon_w^{2/3}\,\textrm{sfc}$','Interpreter','latex')
title(plane)
print(fig,[plotpath,filesep,'uw23_',plane,'_sfc'],'-dpng','-r300')

fig = plot_xy(MOM,{'off_psd_UX'},{'off_psd_W'},levels,'levels',1,1,{'cross3/4','cross1','cross4/3'});
legend(cat(2,levels,dirs),'Location','northwest')
xlabel('$B_L\epsilon_u^{2/3}\,\textrm{psd}$','Interpreter','latex')
ylabel('$B_T\epsilon_w^{2/3}\,\textrm{psd}$','Interpreter','latex')
title(plane)
print(fig,[plotpath,filesep,'uw23_',plane,'_psd'],'-dpng','-r300')


%% (w/u,w/v)^2/3

fig = plot_xy(MOM,{'ar_sfc_WU'},{'ar_sfc_WV'},levels,'levels',1,1,...
    {'cross3/4','cross4/3','ver3/4','ver4/3','hor3/4','hor4/3'});
legend(cat(2,levels,dirs),'Location','southeast')
xlabel('$B_T\epsilon_w^{2/3}/(B_L\epsilon_u^{2/3})\,\textrm{sfc}$','Interpreter','latex')
ylabel('$B_T\epsilon_w^{2/3}/(B_T\epsilon_v^{2/3})\,\textrm{sfc}$','Interpreter','latex')
title(plane)
print(fig,[plotpath,filesep,'ar23_',plane,'_sfc'],'-dpng','-r300')

fig = plot_xy(MOM,{'ar_psd_WU'},{'ar_psd_WV'},levels,'levels',1,1,...
    {'cross3/4','cross4/3','ver3/4','ver4/3','hor3/4','hor4/3'});
legend(cat(2,levels,dirs),'Location','southeast')
xlabel('$C_T\epsilon_w^{2/3}/(C_L\epsilon_u^{2/3})\,\textrm{psd}$','Interpreter','latex')
ylabel('$C_T\epsilon_w^{2/3}/(C_T\epsilon_v^{2/3})\,\textrm{psd}$','Interpreter','latex')
title(plane)
print(fig,[plotpath,filesep,'ar23_',plane,'_psd'],'-dpng','-r300')


%% (s,p)

fig = plot_xy(MOM,{'slp_sfc_W','slp_sfc_UX','slp_sfc_VY'},...
    {'slp_psd_W','slp_psd_UX','slp_psd_VY'},levels,'vars',1,0,{'ver2/3','hor-5/3'});
fig.PaperSize = [20 12]; fig.PaperPosition = [0 0 20 12];
legend(cat(2,vars,levels,dirs),'Location','eastoutside')
xlabel('$s\,\textrm{sfc}$','Interpreter','latex')
ylabel('$s\,\textrm{psd}$','Interpreter','latex')
title(plane)
print(fig,[plotpath,filesep,'slp_',plane],'-dpng','-r300')


%% edr stats

h = plot_whisker(MOM,{'edr_sfc_W','edr_sfc_UX','edr_sfc_VY'},levels,1,...
    'PrimaryLabels',{'W a','W c','UX a','UX c','VY a','VY c'});
ylabel('$\epsilon\,[\mathrm{m^2s^{-3}}]\,\textrm{sfc}$','Interpreter','latex')
title(plane)
print(h.figure,[plotpath,filesep,'edr_wsk_',plane,'_sfc_dir'],'-dpng','-r300')

h = plot_whisker(MOM,{'edr_psd_W','edr_psd_UX','edr_psd_VY'},levels,1,...
    'PrimaryLabels',{'W a','W c','UX a','UX c','VY a','VY c'});
ylabel('$\epsilon\,[\mathrm{m^2s^{-3}}]\,\textrm{psd}$','Interpreter','latex')
title(plane)
print(h.figure,[plotpath,filesep,'edr_wsk_',plane,'_psd_dir'],'-dpng','-r300')


%% edr stats after reversal

h = plot_whisker(MOM,{'edr_sfc_W','edr_sfc_UX','edr_sfc_VY','edr_sfc_UY','edr_sfc_VX'},...
    levels,0,'PrimaryLabels',{'W','UX','VY','UY','VX'});
ylabel('$\epsilon\,[\mathrm{m^2s^{-3}}]\,\textrm{sfc}$','Interpreter','latex')
title(plane)
print(h.figure,[plotpath,filesep,'edr_sfc_wsk_rev'],'-dpng','-r300')

h = plot_whisker(MOM,{'edr_psd_W','edr_psd_UX','edr_psd_VY','edr_psd_UY','edr_psd_VX'},...
    levels,0,'PrimaryLabels',{'W','UX','VY','UY','VX'});
ylabel('$\epsilon\,[\mathrm{m^2s^{-3}}]\,\textrm{psd}$','Interpreter','latex')
title(plane)
print(h.figure,[plotpath,filesep,'edr_psd_wsk_rev'],'-dpng','-r300')


%% integral length scale stats

h = plot_whisker(MOM,{'ls_W'},levels,0,'PrimaryLabels',{'W'});
ylabel('$L,[\mathrm{m}]$','Interpreter','latex')
title(plane)
print(h.figure,[plotpath,filesep,'ls_wsk_W'],'-dpng','-r300')



