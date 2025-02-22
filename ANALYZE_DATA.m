clear all; close all; clc

addpath('data','functions','results','additional_scripts')

show_maps=0; % if show_map=1, thematic maps of the catchment are displayed (this is slow!)
additional_maps=0; % if additional_maps=1, additional maps not shown in the manuscript are produced (this is VERY slow!)

%% Load data
try load('ThurData.mat')
catch
    disp('Extracting the river network...')
    CreateNetwork
end
try load('ThurHydrology.mat')
catch
    disp('Calculating hydological variables...')
    hydrology
end
try load('Covariates.mat')
catch
    disp('Calculating covariates...')
    BuildCovariateMatrix
end
load('GenusData.mat')

CovariateNames={'L-FO';'L-RO';'L-UR';'L-OR';'L-SW';'L-LA';'G-AL';'G-MO';'G-AP';'G-WA';
    'G-LO';'G-SC';'G-PE';'M-US';'M-DA';'M-LS';'M-LE';'M-SO'};

%% Table with ID and genera names
clear tmp
for i=1:length(GeneraOrder)
    tmp{i,1}=[GeneraOrder{i,2},GeneraOrder{i,1}];
end
[~,indAlphabetAll]=sort(tmp);

table([1:length(GeneraOrder)]',GeneraOrder(indAlphabetAll,1),...
    GeneraOrder(indAlphabetAll,2),ismember(GeneraOrder(indAlphabetAll,1),GenusName),...
    ismember(GeneraOrder(indAlphabetAll,1),KicknetName),...
    'VariableNames',{'ID','Genus','Order','eDNA','kicknet'})

% find genera keys
for i=1:length(GenusName)
    eDNA_to_all(i,1)=find(ismember(GeneraOrder(:,1),GenusName(i)));
end
for i=1:length(GeneraOrder)
    all_to_alphabet(i,1)=find(indAlphabetAll==i);
end
all_to_eDNA=nan(length(GeneraOrder),1);
for i=1:length(GeneraOrder)
    tmp=find(ismember(GenusName,GeneraOrder(i,1)));
    if not(isempty(tmp))
        all_to_eDNA(i,1)=tmp;
    end
end

CalibSites=1:numel(SitesReach);
SumGenusPerSite=sum(GenusPerSite,2);
geometry=v2struct(X,Y,XX,YY,Xc,Yc,subcatch,N_reach,AD_pixel,nnodes,outlet,AreaUpstream,reach);

% evaluate geographical covariates and add them to the covariate matrix
RegioCov;
ZCovMat=[ZCovariateMat RegioCovMat(:,1:end-1)];
CovNames=[CovariateNames; RegioCovNames];


%% calculate lateral Q and source area
Qlat=zeros(N_reach,1);
for i=1:N_reach
    subset=find(down_reach==i);
    if ~isempty(subset)
        Qlat(i)=Qjun(i)-sum(Qjun(subset));
    else
        Qlat(i)=Qjun(i);
    end
end
SourceArea=ReachWidth.*length_reach;
PathVelocity=zeros(N_reach);
for i=1:N_reach
    for j=1:N_reach
        path=list_reach_downstream{i,j};
        if ~isempty(path)
            PathVelocity(i,j)=length_downstream(i,j)/(sum(length_reach(path)./Velocity(path)));
        end
    end
end

N_param=size(ZCovMat,2)+2;

%% load colormap Zissou 1
load('colZissou.mat')
colmapZissou=zeros(length(colZissou),3);
for i=1:length(colZissou)
        str=colZissou{i};
        colmapZissou(i,:) = sscanf(str(2:end),'%2x%2x%2x',[1 3])/255;
end

%% READ ResultsAll
DecayTime=zeros(length(GenusName),1); CovariateSign=zeros(N_param-2,length(GenusName));
PresenceMat=zeros(N_reach,length(GenusName)); DetectionProbAll=zeros(N_reach,length(GenusName));

for g=1:length(GenusName)
    Genus=GenusName{g};
    load(['results/all/',Genus])
    quant_par=zeros(N_param,3);
    for i=1:N_param
        quant_par(i,:)=quantile(par(:,i),[0.025 0.5 0.975]);
    end
    ResultsAll.(Genus).DecayTime=exp(quant_par(end,2))/3600;
    ResultsAll.(Genus).param=quant_par(:,2);
    ResultsAll.(Genus).prod=quant_p(12,:)';
    ResultsAll.(Genus).Conc=quant_C(12,:)';
    
    UnconnectedConc=quant_p(12,:)'.*length_reach.*ReachWidth./Qlat.*exp(-length_reach./Velocity./(exp(quant_par(end,2))));
    ResultsAll.(Genus).DetectionProbAll=UnconnectedConc./(1+UnconnectedConc);
    ResultsAll.(Genus).Presence= ResultsAll.(Genus).DetectionProbAll > 0.75;
    ResultsAll.(Genus).CovariateSign=(quant_par(1:N_param-2,1)>0) - (quant_par(1:N_param-2,3)<0);
    
    DecayTime(g)=ResultsAll.(Genus).DecayTime;
    CovariateSign(:,g)=ResultsAll.(Genus).CovariateSign;
    DetectionProbAll(:,g)=ResultsAll.(Genus).DetectionProbAll;
    PresenceMat(:,g)=ResultsAll.(Genus).Presence;
    
    for indSite=1:numel(SitesReach)
        ResultsAll.(Genus).p_value(indSite,1)=GOF_NBtest(ReadNumbers.(Genus)(indSite,:)',ResultsAll.(Genus).Conc(SitesReach(indSite)),100000);
    end
    AcceptedAllSites(g,1)=sum(ResultsAll.(Genus).p_value>0.05);
    AcceptedPerSite(g,:)=ResultsAll.(Genus).p_value>0.05;
end

%% Kicknet vs model - evaulate accuracy
KicknetSiteReach=zeros(length(KicknetSiteID),1);
for i=1:length(KicknetSiteID)
    k=KicknetSiteID(i);
    KicknetSiteReach(i)=SitesReach(find(siteID==k));
end
KicknetPresence=KicknetData>0;
Site_eDNAkick=find(ismember(siteID,KicknetSiteID));% ReadNumbers.(Genus)(Site_eDNAKick) are read numbers at the same sites as kicknet

KicknetVsModel_mat=zeros(length(KicknetSiteID),length(GeneraOrder));
Scores_eDNAKick=zeros(length(GeneraOrder),1);
TruePositiveAll=zeros(length(GeneraOrder),5); TrueNegativeAll=zeros(length(GeneraOrder),5);
FalsePositiveAll=zeros(length(GeneraOrder),5); FalseNegativeAll=zeros(length(GeneraOrder),5);
TruePositiveAll_eDNA=zeros(length(GeneraOrder),5); TrueNegativeAll_eDNA=zeros(length(GeneraOrder),5);
FalsePositiveAll_eDNA=zeros(length(GeneraOrder),5); FalseNegativeAll_eDNA=zeros(length(GeneraOrder),5);

for i=1:length(GeneraOrder)
    Genus=GeneraOrder{i,1};
    % read model and eDNA
    if sum(strcmp(cellstr(GenusName),Genus))>0
        % eDITH
        ind_model=find(strcmp(cellstr(GenusName),Genus));
        presence_probAll=DetectionProbAll(KicknetSiteReach,ind_model);
        presence_probAll(presence_probAll<1e-50)=1e-50;
        % eDNA data
        presence_prob_eDNA=sum(ReadNumbers.(Genus)>0,2)/3;
        presence_prob_eDNA=presence_prob_eDNA(Site_eDNAkick);
    else
        presence_probAll=1e-50*ones(length(KicknetSiteReach),1);
        presence_prob_eDNA=1e-50*ones(length(KicknetSiteReach),1);
    end
    % read kicknet data
    if sum(strcmp(cellstr(KicknetName),Genus))>0
        ind_kicknet=find(strcmp(cellstr(KicknetName),Genus));
        presence_kick=KicknetPresence(:,ind_kicknet);
    else
        presence_kick=zeros(length(KicknetSiteReach),1);
    end
    % calculate probability
    for j=1:length(KicknetSiteReach)
        s=stream_order_reach(KicknetSiteReach(j));
        if presence_kick(j)==1
            Scores_eDNAKick(i) = Scores_eDNAKick(i) + log(presence_probAll(j));
            if presence_probAll(j) >= 2/3
                TruePositiveAll(i,s) = TruePositiveAll(i,s) + 1;
                KicknetVsModel_mat(j,i)=1;
            else
                FalseNegativeAll(i,s) = FalseNegativeAll(i,s) + 1;
                KicknetVsModel_mat(j,i)=2;
            end
            if presence_prob_eDNA(j) >= 2/3
                TruePositiveAll_eDNA(i,s) = TruePositiveAll_eDNA(i,s) + 1;
            else
                FalseNegativeAll_eDNA(i,s) = FalseNegativeAll_eDNA(i,s) + 1;
            end
        else
            Scores_eDNAKick(i) = Scores_eDNAKick(i) + log(1-presence_probAll(j));
            if presence_probAll(j) >= 2/3
                FalsePositiveAll(i,s) = FalsePositiveAll(i,s) + 1;
                KicknetVsModel_mat(j,i)=3;
            else
                TrueNegativeAll(i,s) = TrueNegativeAll(i,s) + 1;
                KicknetVsModel_mat(j,i)=4;
            end
            if presence_prob_eDNA(j) >= 2/3
                FalsePositiveAll_eDNA(i,s) = FalsePositiveAll_eDNA(i,s) + 1;
            else
                TrueNegativeAll_eDNA(i,s) = TrueNegativeAll_eDNA(i,s) + 1;
            end
        end
    end
end
TP=sum(TruePositiveAll,2); FP=sum(FalsePositiveAll,2); 
TN=sum(TrueNegativeAll,2); FN=sum(FalseNegativeAll,2); 
AccuracyAll=(TP+TN)/length(KicknetSiteReach);
AccuracywFPAll=(TP+TN+FP)/length(KicknetSiteReach);
% eval accuracy per stream order
Accuracy_SO=zeros(length(GeneraOrder),4); Accuracy_SO_FP=zeros(length(GeneraOrder),4);
for i=1:3
Accuracy_SO(:,i)=(TruePositiveAll(:,i)+TrueNegativeAll(:,i))/sum(stream_order_reach(KicknetSiteReach)==i);
Accuracy_SO_FP(:,i)=(TruePositiveAll(:,i)+TrueNegativeAll(:,i)+FalsePositiveAll(:,i))/sum(stream_order_reach(KicknetSiteReach)==i);
end
Accuracy_SO(:,4)=(sum(TruePositiveAll(:,4:5),2)+sum(TrueNegativeAll(:,4:5),2))/sum(stream_order_reach(KicknetSiteReach)>3);
Accuracy_SO_FP(:,4)=(sum(TruePositiveAll(:,4:5),2)+sum(TrueNegativeAll(:,4:5),2)+sum(FalsePositiveAll(:,4:5),2))/sum(stream_order_reach(KicknetSiteReach)>3);

TP_eDNA=sum(TruePositiveAll_eDNA,2); FP_eDNA=sum(FalsePositiveAll_eDNA,2); 
TN_eDNA=sum(TrueNegativeAll_eDNA,2); FN_eDNA=sum(FalseNegativeAll_eDNA,2);
AccuracyAll_eDNA=(TP_eDNA + TN_eDNA)/length(KicknetSiteReach);
AccuracywFPAll_eDNA=(TP_eDNA + TN_eDNA + FP_eDNA)/length(KicknetSiteReach);
% eval accuracy per stream order
Accuracy_SO_eDNA=zeros(length(GeneraOrder),4); Accuracy_SO_FP_eDNA=zeros(length(GeneraOrder),4);
for i=1:3
Accuracy_SO_eDNA(:,i)=(TruePositiveAll_eDNA(:,i)+TrueNegativeAll_eDNA(:,i))/sum(stream_order_reach(KicknetSiteReach)==i);
Accuracy_SO_FP_eDNA(:,i)=(TruePositiveAll_eDNA(:,i)+TrueNegativeAll_eDNA(:,i)+FalsePositiveAll_eDNA(:,i))/sum(stream_order_reach(KicknetSiteReach)==i);
end
Accuracy_SO_eDNA(:,4)=(sum(TruePositiveAll_eDNA(:,4:5),2)+sum(TrueNegativeAll_eDNA(:,4:5),2))/sum(stream_order_reach(KicknetSiteReach)>3);
Accuracy_SO_FP_eDNA(:,4)=(sum(TruePositiveAll_eDNA(:,4:5),2)+sum(TrueNegativeAll_eDNA(:,4:5),2)+sum(FalsePositiveAll_eDNA(:,4:5),2))/sum(stream_order_reach(KicknetSiteReach)>3);


[~,indScore]=sort(Scores_eDNAKick,'descend');
[~,indAccuracy]=sort(AccuracyAll,'descend');
indAccuracy2=indAccuracy;
for i=1:length(indAccuracy)
    if ismember(GeneraOrder(indAccuracy(i),1),GenusName)==0
        indAccuracy2(i)=0;
    end
end
indAccuracy2(indAccuracy2==0)=[];

table(cellstr(GeneraOrder(indAccuracy,1)),Scores_eDNAKick(indAccuracy),TP(indAccuracy),FP(indAccuracy),...
    TN(indAccuracy),FN(indAccuracy),AccuracyAll(indAccuracy),...
    'Variablenames',{'Genus','Score','TP_all','FP_all','TN_all','FN_all','ACC_all'})

% display accuracy by TP, TN, FP, FN
[~,indFN_all]=sort(1e6*FN-TP-TN,'ascend');
indFN=indFN_all(ismember(GeneraOrder(indFN_all,1),GenusName)); % pick only the genera detected by eDNA
figure; 
b=bar([TP(indFN)/60 TN(indFN)/60 FP(indFN)/60 FN(indFN)/60],0.85,'stacked',...
    'facecolor','flat','edgecolor','n');  box off;
colormap([0 0.3 0; 0 0.6 0; 0.7 0.7 0; 1 0 0]);
for k = 1:4
    b(k).CData = k;
end
xtickangle(60); ylabel('Fraction of sites')
legend('TP','TN','FP','FN','location','eastoutside'); legend boxoff
set(gca,'tickdir','out','ylim',[0 1],'ytick',[0:0.25:1],'xtick',[1:50],'xticklabel',1:50) %all_to_alphabet(indFN)

% index used for subsequent plots
which_indFN=nan(length(GeneraOrder),1);
for i=1:length(GeneraOrder)
    if not(isempty( find(indFN==i) ))
        which_indFN(i) = find(indFN==i);
    end
end

%% Map of kicknet and eDNA richness
zismap=colmapZissou(round(linspace(1,length(colmapZissou),21)),:);
jetmap=jet(21);
AllRichness=sum(PresenceMat,2);
KicknetRichness=sum(KicknetPresence,2);
KicknetSiteX=siteX(ismember(siteID,KicknetSiteID));
KicknetSiteY=siteY(ismember(siteID,KicknetSiteID));
eDNA_richness=zeros(length(siteID),1);
for i=1:length(GenusName)
    Genus=GenusName{i};
    tmp=ReadNumbers.(Genus)>1;
    tmp=sum(tmp,2);
    presence=tmp>1;
    eDNA_richness=eDNA_richness+presence;
end

if show_maps
    f1=DrawRiverMap(nan(N_reach,1),20,0,'Kicknet richness','JET',geometry,1,1);
    hold on;
    for i=1:length(KicknetSiteID)
        plot(KicknetSiteX(i),KicknetSiteY(i),'o','markerfacecolor',...
            jetmap(KicknetRichness(i)+1,:),'markeredgecolor','k')
    end
    set(gcf,'Renderer','painters'); saveas(f1,'KicknetRichness.pdf');
    f1=DrawRiverMap(nan(N_reach,1),20,0,'eDNA richness','JET',geometry,1,1);
    hold on;
    for i=1:length(siteID)
        plot(siteX(i),siteY(i),'o','markerfacecolor',jetmap(eDNA_richness(i)+1,:),'markeredgecolor','k')
    end
    set(gcf,'Renderer','painters'); saveas(f1,'eDNARichness.pdf');
    f1=DrawRiverMap(AllRichness,20,0,'eDITH richness','JET',geometry,1,1,colmapZissou);
    set(gcf,'Renderer','painters'); saveas(f1,'eDITHRichness.pdf');
end

% prepare data for csv export
dataframe=cell(N_reach+length(SitesReach)+length(Site_eDNAkick),2);
k=1;
for i=1:N_reach
    dataframe{k,1}='eDITH'; dataframe{k,2}=AllRichness(i); k=k+1;
end
for i=1:length(SitesReach)
    dataframe{k,1}='eDNA'; dataframe{k,2}=eDNA_richness(i); k=k+1;
end
for i=1:length(Site_eDNAkick)
    dataframe{k,1}='kicknet'; dataframe{k,2}=KicknetRichness(i); k=k+1;
end

T=table(dataframe(:,1),[dataframe{:,2}]','VariableNames',{'Type','GenusRichness'});
writetable(T,'source_data/Fig5.csv')

%% boxplots of richness per stream order
dbp=cell(4,3); 
for i=1:3
    dbp{i,1}=AllRichness(stream_order_reach==i);
    dbp{i,2}=eDNA_richness(stream_order_reach(SitesReach)==i);
    dbp{i,3}=KicknetRichness(stream_order_reach(KicknetSiteReach)==i);
end
dbp{4,1}=AllRichness(stream_order_reach>3);
dbp{4,2}=eDNA_richness(stream_order_reach(SitesReach)>3);
dbp{4,3}=KicknetRichness(stream_order_reach(KicknetSiteReach)>3);
cmap=[0.2 0.8 0 0.8; 
    1 0.5 0 0.8; 
    0.6 0 1 0.8];
figure; multiple_boxplot(dbp,{'1','2','3','>3',},{'eDITH','eDNA','kicknet'},cmap');
box off; xlabel('Strahler stream order'); ylabel('Genera richness')
set(gca,'tickdir','out','ytick',[0:5:20]); legend boxoff
title([histcounts(stream_order_reach) histcounts(stream_order_reach(KicknetSiteReach))])

% perform 2-sample KS test
logicalStr={'TRUE';'FALSE'};
[h,p]=kstest2(dbp{1,1},dbp{1,3});
disp(sprintf(['H0: eDITH and kicknet have same distribution for stream order 1: ',logicalStr{h+1},'    p: ',num2str(p)]))
[h,p]=kstest2(dbp{1,2},dbp{1,3});
disp(sprintf(['H0: eDNA and kicknet have same distribution for stream order 1: ',logicalStr{h+1},'    p: ',num2str(p)]))
[h,p]=kstest2(dbp{4,1},dbp{4,2});
disp(sprintf(['H0: eDITH and kicknet have same distribution for stream order > 3: ',logicalStr{h+1},'    p: ',num2str(p)]))
[h,p]=kstest2(dbp{4,2},dbp{4,3});
disp(sprintf(['H0: eDNA and kicknet have same distribution for stream order > 3: ',logicalStr{h+1},'    p: ',num2str(p)]))

% prepare data for export in csv
dataframe=cell(N_reach+length(SitesReach)+length(Site_eDNAkick),3);
k=1; tmp=length(dbp{1,1});
for i=1:tmp
dataframe{k,1}='eDITH'; dataframe{k,2}=1; dataframe{k,3}=dbp{1,1}(i);
k=k+1;
end
tmp=length(dbp{2,1});
for i=1:tmp
dataframe{k,1}='eDITH'; dataframe{k,2}=2; dataframe{k,3}=dbp{2,1}(i);
k=k+1;
end
tmp=length(dbp{3,1});
for i=1:tmp
dataframe{k,1}='eDITH'; dataframe{k,2}=3; dataframe{k,3}=dbp{3,1}(i);
k=k+1;
end
tmp=length(dbp{4,1});
for i=1:tmp
dataframe{k,1}='eDITH'; dataframe{k,2}=4; dataframe{k,3}=dbp{4,1}(i);
k=k+1;
end
tmp=length(dbp{1,2});
for i=1:tmp
dataframe{k,1}='eDNA'; dataframe{k,2}=1; dataframe{k,3}=dbp{1,1}(i);
k=k+1;
end
tmp=length(dbp{2,2});
for i=1:tmp
dataframe{k,1}='eDNA'; dataframe{k,2}=2; dataframe{k,3}=dbp{2,1}(i);
k=k+1;
end
tmp=length(dbp{3,2});
for i=1:tmp
dataframe{k,1}='eDNA'; dataframe{k,2}=3; dataframe{k,3}=dbp{3,1}(i);
k=k+1;
end
tmp=length(dbp{4,2});
for i=1:tmp
dataframe{k,1}='eDNA'; dataframe{k,2}=4; dataframe{k,3}=dbp{4,1}(i);
k=k+1;
end
tmp=length(dbp{1,3});
for i=1:tmp
dataframe{k,1}='Kicknet'; dataframe{k,2}=1; dataframe{k,3}=dbp{1,1}(i);
k=k+1;
end
tmp=length(dbp{2,3});
for i=1:tmp
dataframe{k,1}='Kicknet'; dataframe{k,2}=2; dataframe{k,3}=dbp{2,1}(i);
k=k+1;
end
tmp=length(dbp{3,3});
for i=1:tmp
dataframe{k,1}='Kicknet'; dataframe{k,2}=3; dataframe{k,3}=dbp{3,1}(i);
k=k+1;
end
tmp=length(dbp{4,3});
for i=1:tmp
dataframe{k,1}='Kicknet'; dataframe{k,2}=4; dataframe{k,3}=dbp{4,1}(i);
k=k+1;
end

T=table(dataframe(:,1),[dataframe{:,2}]',[dataframe{:,3}]','VariableNames',{'Type','StreamOrder','GenusRichness'});
writetable(T,'source_data/Fig6.csv')

%% covariate table ordered by indFN
cmapITA3=[1 0 0; 1 1 1; 0 1 0];
figure; imagesc(CovariateSign(:,all_to_eDNA(indFN))'); colormap(cmapITA3); cb=colorbar; cb.Ticks=[-1; 0; 1];
set(gca,'tickdir','out','ytick',1:50,'yticklabel',[1:50],'xtick',1:N_param-2,'xticklabel',CovNames)
xtickangle(60)
figure('units','normalized','outerposition',[0 0 1 1]); imagesc(CovariateSign(:,all_to_eDNA(indFN))'); colormap(cmapITA3); cb=colorbar; cb.Ticks=[-1; 0; 1];
set(gca,'tickdir','out','ytick',1:50,'yticklabel',GeneraOrder(indFN,1),'xtick',1:N_param-2,'xticklabel',CovNames)
xtickangle(60)

%% Goodness-of-Fit histogram
figure; bar(AcceptedAllSites(all_to_eDNA(indFN))/length(siteID),'facecolor',[0.5 0.5 0.5]); box on
box off; set(gca,'tickdir','out','ytick',[0:0.25:1],'xtick',1:50,'xticklabel',[1:50])
xtickangle(60)
ylabel('Fraction of sites where H_0 cannot be rejected')

%% covariates' effect
% tornado plots
PositiveEffect=sum(CovariateSign==1,2);
NegativeEffect=sum(CovariateSign==-1,2);

[~,indTornado1]=sort(PositiveEffect(1:18)+NegativeEffect(1:18));
figure; h = barh(PositiveEffect(indTornado1),'g'); hold on
barh(-NegativeEffect(indTornado1),'r')
bh = get(h,'BaseLine');
set(bh,'BaseValue',0);
set(gca,'Ytick',[1:18],'YTickLabel',[1:18])
set(gca,'yticklabel',cellstr(CovNames(indTornado1)),'xlim',[-20 15],'xtick',[-20:5:15],'xticklabel',abs([-20:5:15]))
xlabel('Number of genera')
legend('Positive','Negative','location','southwest'); legend boxoff

[~,indTornado2]=sort(PositiveEffect(19:35)+NegativeEffect(19:35));
indTornado2=indTornado2+18;
figure; h = barh(PositiveEffect(indTornado2),'g'); hold on
barh(-NegativeEffect(indTornado2),'r')
bh = get(h,'BaseLine');
set(bh,'BaseValue',0);
set(gca,'Ytick',[1:17],'YTickLabel',[1:17])
set(gca,'yticklabel',cellstr(CovNames(indTornado2)),'xlim',[-20 15],'xtick',[-20:5:15],'xticklabel',abs([-20:5:15]))
xlabel('Number of genera')
legend('Positive','Negative','location','southwest'); legend boxoff

%% Decay times
table(cellstr(GenusName),DecayTime)
[~,indDecayTime]=sort(DecayTime,'descend');
f=figure; bar(DecayTime(indDecayTime),'facecolor',[0.5 0.5 0.5]); box off
set(gca,'tickdir','out','ylim',[0 10],'ytick',[0:5:10],'xtick',[1:50],'xticklabel',which_indFN(eDNA_to_all(indDecayTime))) %GeneraOrder((eDNA_to_all(indDecayTime)),1)
xtickangle(60); ylabel('Decay time [h]')
yyaxis right
ax=gca;
set(gca,'tickdir','out','ylim',[0 10*3.6],'ytick',[0:10:30])
ylabel('Decay distance [km]')


T=table(which_indFN(eDNA_to_all(indDecayTime)),GeneraOrder(eDNA_to_all(indDecayTime),1),DecayTime(indDecayTime),...
    'VariableNames',{'GenusID','GenusName','DecayTime'});
writetable(T,'source_data/Fig3.csv')

%% Richness maps
if show_maps
    f1=DrawRiverMap(ResultsAll.Habroleptoides.DetectionProbAll,1,0,'Habroleptoides (Ephemeroptera)','ZIS',geometry,1,1,colmapZissou);
    set(gcf,'Renderer','painters'); saveas(f1,'HabroDetProb.pdf'); 
    f1=DrawRiverMap(ResultsAll.Protonemura.DetectionProbAll,1,0,'Protonemura (Plecoptera)','ZIS',geometry,1,1,colmapZissou);
    set(gcf,'Renderer','painters'); saveas(f1,'ProtonemuraDetProb.pdf'); 
    f1=DrawRiverMap(ResultsAll.Athripsodes.DetectionProbAll,1,0,'Athripsodes (Trichoptera)','ZIS',geometry,1,1,colmapZissou);
    set(gcf,'Renderer','painters'); saveas(f1,'AthripsDetProb.pdf'); 
    f1=DrawRiverMap(log10(ResultsAll.Habroleptoides.prod),0,-6,'Habroleptoides (Ephemeroptera)','ZIS',geometry,1,1,colmapZissou);
    set(gcf,'Renderer','painters'); saveas(f1,'HabroProd.pdf'); 
    f1=DrawRiverMap(log10(ResultsAll.Protonemura.prod),0,-6,'Protonemura (Plecoptera)','ZIS',geometry,1,1,colmapZissou);
    set(gcf,'Renderer','painters'); saveas(f1,'ProtonemuraProd.pdf'); 
    f1=DrawRiverMap(log10(ResultsAll.Athripsodes.prod),0,-6,'Athripsodes (Trichoptera)','ZIS',geometry,1,1,colmapZissou);
    set(gcf,'Renderer','painters'); saveas(f1,'AthrisProd.pdf'); 
end

T=table(ResultsAll.Habroleptoides.prod,ResultsAll.Protonemura.prod,ResultsAll.Athripsodes.prod,...
    ResultsAll.Habroleptoides.DetectionProbAll,ResultsAll.Protonemura.DetectionProbAll,ResultsAll.Athripsodes.DetectionProbAll,...
    'VariableNames',{'HabroleptoidesDensity','ProtonemuraDensity','AthripsodesDensity','HabroleptoidesDetProb','ProtonemuraDetProb','AthripsodesDetProb'});
writetable(T,'source_data/Fig4.csv')

%% Detection probability maps for all genera
if additional_maps
    tic
    for i=1:length(GenusName)
        Genus=GenusName{i};
        j=find(ismember(GeneraOrder(:,1),Genus));
        disp(sprintf('#%d. - %s',i,Genus));
        f2=DrawRiverMap(ResultsAll.(Genus).DetectionProbAll,1,0,[Genus,' (',GeneraOrder{j,2},')'],'GER',geometry,1,1);
        saveas(f2,[Genus,'.png']); close all;
        toc
    end
end

%% Plot maps of richness by order
if additional_maps
    EphemGenera=[]; PlecoGenera=[]; TrichGenera=[];
    for i=1:length(GenusName)
        index=find(strcmp(GeneraOrder(:,1),GenusName{i}));
        if strcmp(GeneraOrder{index,2},'Ephemeroptera')
            EphemGenera = [EphemGenera; i];
        elseif strcmp(GeneraOrder{index,2},'Plecoptera')
            PlecoGenera = [PlecoGenera; i];
        elseif strcmp(GeneraOrder{index,2},'Trichoptera')
            TrichGenera = [TrichGenera; i];
        end
    end
    EphemeropteraRichness=sum(PresenceMat(:,EphemGenera),2);
    PlecopteraRichness=sum(PresenceMat(:,PlecoGenera),2);
    TrichopteraRichness=sum(PresenceMat(:,TrichGenera),2);
    
    DrawRiverMap(EphemeropteraRichness,max(EphemeropteraRichness),0,'Richness of Ephemeroptera genera','GER',geometry,1,1);
    DrawRiverMap(PlecopteraRichness,max(PlecopteraRichness),0,'Richness of Plecoptera genera','GER',geometry,1,1);
    DrawRiverMap(TrichopteraRichness,max(TrichopteraRichness),0,'Richness of Trichoptera genera','GER',geometry,1,1);
end

%% draw maps of kicknet vs model
if additional_maps
    for i=1:length(GeneraOrder)
        f2=figure; gplot(AD_pixel,[X,Y]); hold on; plot(Xc,Yc,'k'); axis off; axis equal; box off
        set(gca,'xlim',[min(Xc)-2700 max(Xc)],'ylim',[min(Yc) max(Yc)])
        l_TP=plot([KicknetSiteX(KicknetVsModel_mat(:,i)==1); 0],[KicknetSiteY(KicknetVsModel_mat(:,i)==1); 0],...
            'o','markerfacecolor',[0 0.5 0],'markeredgecolor',[0 0.5 0]); %TP
        l_FP=plot([KicknetSiteX(KicknetVsModel_mat(:,i)==3); 0],[KicknetSiteY(KicknetVsModel_mat(:,i)==3); 0],...
            'xr','markersize',10,'linewidth',2); %FP
        l_FN=plot([KicknetSiteX(KicknetVsModel_mat(:,i)==2); 0],[KicknetSiteY(KicknetVsModel_mat(:,i)==2); 0],...
            'x','markeredgecolor',[0 0.5 0],'markersize',10,'linewidth',2); %FN
        l_TN=plot([KicknetSiteX(KicknetVsModel_mat(:,i)==4); 0],[KicknetSiteY(KicknetVsModel_mat(:,i)==4); 0],...
            'or','markerfacecolor','r'); %TN
        legend([l_TP l_FP l_FN l_TN],{['TP = ',num2str(TruePositive(i))],['FP = ',num2str(FalsePositive(i))],...
            ['FN = ',num2str(FalseNegative(i))],['TN = ',num2str(TrueNegative(i))]},'location','southwest')
        legend boxoff
        title(sprintf([GeneraOrder{i},' - accuracy = %.0f%%'],AccuracyAll(i)*100))
        saveas(f2,[GeneraOrder{i},'.png']); close all;
    end
end

%% SUBSAMPLING
% read Results
try load('results/subsampling_results.mat')
catch
    Results=[];
    for N_ValidSites=12:12:36
        for RUN=1:3
            N_ValidSites
            RUN
            Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).AcceptedAllSites=zeros(length(GenusName),1);
            Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).DetectionProb=zeros(length(GenusName),N_reach);
            for g=1:length(GenusName)
                Genus=GenusName{g};
                load(['results/subsampling_',num2str(N_ValidSites),'_',num2str(RUN),'/',Genus])
                quant_par=zeros(N_param,3);
                for i=1:N_param
                    quant_par(i,:)=quantile(par(:,i),[0.025 0.5 0.975]);
                end
                UnconnectedConc=quant_p(12,:)'.*length_reach.*ReachWidth./Qlat.*exp(-length_reach./Velocity./(exp(quant_par(end,2))));
                Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).(Genus).DetectionProb=UnconnectedConc./(1+UnconnectedConc);
                Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).ValidSites=ValidSites;
                CalibSites=setdiff(1:61,ValidSites);
                Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).(Genus).Conc=quant_C(12,:)';
                for indSite=1:numel(SitesReach)
                    Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).(Genus).p_value(indSite,1)=...
                        GOF_NBtest(ReadNumbers.(Genus)(indSite,:)',Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).(Genus).Conc(SitesReach(indSite)),100000);
                end
                Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).GOF(g,1)=...
                    sum(Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).(Genus).p_value>0.05);
                Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).GOFcalib(g,1)=...
                    sum(Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).(Genus).p_value(CalibSites)>0.05);
                Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).GOFvalid(g,1)=...
                    sum(Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).(Genus).p_value(ValidSites)>0.05);
                Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).DetectionProb(g,:)=...
                    Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).(Genus).DetectionProb;
            end
            [TP,TN,FP,FN] = eval_accuracy(Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).DetectionProb,...
                KicknetPresence,Site_eDNAkick,SitesReach,2/3,GenusName,KicknetName);
            Results.(['v',num2str(N_ValidSites)]).(['r',num2str(RUN)]).Accuracy=(TP+TN)/length(Site_eDNAkick);
        end
    end
    ValidSites_v12=[Results.v12.r1.ValidSites Results.v12.r2.ValidSites Results.v12.r3.ValidSites];
    ValidSites_v24=[Results.v24.r1.ValidSites Results.v24.r2.ValidSites Results.v24.r3.ValidSites];
    ValidSites_v36=[Results.v36.r1.ValidSites Results.v36.r2.ValidSites Results.v36.r3.ValidSites];
    GOF_v12=[Results.v12.r1.GOF(all_to_eDNA(indFN)) Results.v12.r2.GOF(all_to_eDNA(indFN)) Results.v12.r3.GOF(all_to_eDNA(indFN))];
    GOF_v24=[Results.v24.r1.GOF(all_to_eDNA(indFN)) Results.v24.r2.GOF(all_to_eDNA(indFN)) Results.v24.r3.GOF(all_to_eDNA(indFN))];
    GOF_v36=[Results.v36.r1.GOF(all_to_eDNA(indFN)) Results.v36.r2.GOF(all_to_eDNA(indFN)) Results.v36.r3.GOF(all_to_eDNA(indFN))];
    GOFcalib_v12=[Results.v12.r1.GOFcalib(all_to_eDNA(indFN)) Results.v12.r2.GOFcalib(all_to_eDNA(indFN)) Results.v12.r3.GOFcalib(all_to_eDNA(indFN))];
    GOFcalib_v24=[Results.v24.r1.GOFcalib(all_to_eDNA(indFN)) Results.v24.r2.GOFcalib(all_to_eDNA(indFN)) Results.v24.r3.GOFcalib(all_to_eDNA(indFN))];
    GOFcalib_v36=[Results.v36.r1.GOFcalib(all_to_eDNA(indFN)) Results.v36.r2.GOFcalib(all_to_eDNA(indFN)) Results.v36.r3.GOFcalib(all_to_eDNA(indFN))];
    GOFvalid_v12=[Results.v12.r1.GOFvalid(all_to_eDNA(indFN)) Results.v12.r2.GOFvalid(all_to_eDNA(indFN)) Results.v12.r3.GOFvalid(all_to_eDNA(indFN))];
    GOFvalid_v24=[Results.v24.r1.GOFvalid(all_to_eDNA(indFN)) Results.v24.r2.GOFvalid(all_to_eDNA(indFN)) Results.v24.r3.GOFvalid(all_to_eDNA(indFN))];
    GOFvalid_v36=[Results.v36.r1.GOFvalid(all_to_eDNA(indFN)) Results.v36.r2.GOFvalid(all_to_eDNA(indFN)) Results.v36.r3.GOFvalid(all_to_eDNA(indFN))];
    Accuracy_v12=[Results.v12.r1.Accuracy(all_to_eDNA(indFN)) Results.v12.r2.Accuracy(all_to_eDNA(indFN)) Results.v12.r3.Accuracy(all_to_eDNA(indFN))];
    Accuracy_v24=[Results.v24.r1.Accuracy(all_to_eDNA(indFN)) Results.v24.r2.Accuracy(all_to_eDNA(indFN)) Results.v24.r3.Accuracy(all_to_eDNA(indFN))];
    Accuracy_v36=[Results.v36.r1.Accuracy(all_to_eDNA(indFN)) Results.v36.r2.Accuracy(all_to_eDNA(indFN)) Results.v36.r3.Accuracy(all_to_eDNA(indFN))];
    save('results/subsampling_results.mat','GOF_v12','GOF_v24','GOF_v36','GOFcalib_v12','GOFcalib_v24','GOFcalib_v36',...
        'GOFvalid_v12','GOFvalid_v24','GOFvalid_v36','Accuracy_v12','Accuracy_v24','Accuracy_v36',...
        'ValidSites_v12','ValidSites_v24','ValidSites_v36')
end

%% subsampling - figure GOF
figure('units','centimeters','position',[0 0 21 4.5]);
bar(AcceptedAllSites(all_to_eDNA(indFN))/61,'FaceColor','n'); hold on; box off
set(gca,'tickdir','out','ytick',[0:0.2:1],'xtick',[1:50],'ylim',[0.6 1])
ylabel('Fraction of sites where H_0 cannot be rejected')

plot((1:50)-0.2,GOF_v12(:,1)/61,'ob');
plot((1:50)-0.2,GOF_v12(:,2)/61,'+b');
plot((1:50)-0.2,GOF_v12(:,3)/61,'xb');
for i=1:length(GenusName)
    plot([i-0.2 i-0.2],[min(GOF_v12(i,:)) max(GOF_v12(i,:))]/61,'b')
end

plot((1:50),GOF_v24(:,1)/61,'or');
plot((1:50),GOF_v24(:,2)/61,'+r');
plot((1:50),GOF_v24(:,3)/61,'xr');
for i=1:length(GenusName)
    plot([i i],[min(GOF_v24(i,:)) max(GOF_v24(i,:))]/61,'r')
end

plot((1:50)+0.2,GOF_v36(:,1)/61,'og');
plot((1:50)+0.2,GOF_v36(:,2)/61,'+g');
plot((1:50)+0.2,GOF_v36(:,3)/61,'xg');
for i=1:length(GenusName)
    plot([i i]+0.2,[min(GOF_v36(i,:)) max(GOF_v36(i,:))]/61,'g')
end

%% evaluate LossOfGOF
LossOfGOF=zeros(length(GenusName),3);
for g=1:length(GenusName)
    LossOfGOF(g,1)=mean(GOF_v12(g,:)-AcceptedAllSites(all_to_eDNA(indFN(g))))/61;
    LossOfGOF(g,2)=mean(GOF_v24(g,:)-AcceptedAllSites(all_to_eDNA(indFN(g))))/61;
    LossOfGOF(g,3)=mean(GOF_v36(g,:)-AcceptedAllSites(all_to_eDNA(indFN(g))))/61;
end

LossOfGOFcalib=zeros(length(GenusName),3);
for g=1:length(GenusName)
    tmp12=zeros(1,3); tmp24=zeros(1,3); tmp36=zeros(1,3);
    for r=1:3
        tmp12(:,r)=sum(AcceptedPerSite(all_to_eDNA(indFN(g)),setdiff(1:61,ValidSites_v12(:,r))));
        tmp24(:,r)=sum(AcceptedPerSite(all_to_eDNA(indFN(g)),setdiff(1:61,ValidSites_v24(:,r))));
        tmp36(:,r)=sum(AcceptedPerSite(all_to_eDNA(indFN(g)),setdiff(1:61,ValidSites_v36(:,r))));
    end
    LossOfGOFcalib(g,1)=mean(GOFcalib_v12(g,:)-tmp12)/(61-12);
    LossOfGOFcalib(g,2)=mean(GOFcalib_v24(g,:)-tmp24)/(61-24);
    LossOfGOFcalib(g,3)=mean(GOFcalib_v36(g,:)-tmp36)/(61-36);
end

LossOfGOFvalid=zeros(length(GenusName),3);
for g=1:length(GenusName)
    tmp12=zeros(1,3); tmp24=zeros(1,3); tmp36=zeros(1,3);
    for r=1:3
        tmp12(:,r)=sum(AcceptedPerSite(all_to_eDNA(indFN(g)),ValidSites_v12(:,r)));
        tmp24(:,r)=sum(AcceptedPerSite(all_to_eDNA(indFN(g)),ValidSites_v24(:,r)));
        tmp36(:,r)=sum(AcceptedPerSite(all_to_eDNA(indFN(g)),ValidSites_v36(:,r)));
    end
    LossOfGOFvalid(g,1)=mean(GOFvalid_v12(g,:)-tmp12)/12;
    LossOfGOFvalid(g,2)=mean(GOFvalid_v24(g,:)-tmp24)/24;
    LossOfGOFvalid(g,3)=mean(GOFvalid_v36(g,:)-tmp36)/36;
end

% mean (across genera) Loss of accuracy due to reduction in number of sampling sites
MeanLossOfGOF = mean(LossOfGOF)
MeanLossOfGOFcalib = mean(LossOfGOFcalib)
MeanLossOfGOFvalid = mean(LossOfGOFvalid)


%% subsampling - figure accuracy
figure('units','centimeters','position',[0 0 21 4.5]);
bar(AccuracyAll(indFN),'FaceColor','n'); hold on; box off
set(gca,'tickdir','out','ytick',[0.25:0.25:1],'xtick',[1:50],'ylim',[0.25 1])
ylabel('Accuracy')

plot((1:50)-0.2,Accuracy_v12(:,1),'ob');
plot((1:50)-0.2,Accuracy_v12(:,2),'+b');
plot((1:50)-0.2,Accuracy_v12(:,3),'xb');
for i=1:length(GenusName)
    plot([i-0.2 i-0.2],[min(Accuracy_v12(i,:)) max(Accuracy_v12(i,:))],'b')
end

plot((1:50),Accuracy_v24(:,1),'or');
plot((1:50),Accuracy_v24(:,2),'+r');
plot((1:50),Accuracy_v24(:,3),'xr');
for i=1:length(GenusName)
    plot([i i],[min(Accuracy_v24(i,:)) max(Accuracy_v24(i,:))],'r')
end

plot((1:50)+0.2,Accuracy_v36(:,1),'og');
plot((1:50)+0.2,Accuracy_v36(:,2),'+g');
plot((1:50)+0.2,Accuracy_v36(:,3),'xg');
for i=1:length(GenusName)
    plot([i i]+0.2,[min(Accuracy_v36(i,:)) max(Accuracy_v36(i,:))],'g')
end

% export csv for Figure 7
T=table([1:50]',GeneraOrder(indFN,1),TP(indFN)/length(Site_eDNAkick),TN(indFN)/length(Site_eDNAkick),...
    FP(indFN)/length(Site_eDNAkick),FN(indFN)/length(Site_eDNAkick),...
    AcceptedAllSites(all_to_eDNA(indFN))/length(siteID),...
    Accuracy_v12(:,1),Accuracy_v12(:,2),Accuracy_v12(:,3),...
    Accuracy_v24(:,1),Accuracy_v24(:,2),Accuracy_v24(:,3),...
    Accuracy_v36(:,1),Accuracy_v36(:,2),Accuracy_v36(:,3),...
    GOF_v12(:,1)/length(siteID),GOF_v12(:,2)/length(siteID),GOF_v12(:,3)/length(siteID),...
    GOF_v24(:,1)/length(siteID),GOF_v24(:,2)/length(siteID),GOF_v24(:,3)/length(siteID),...
    GOF_v36(:,1)/length(siteID),GOF_v36(:,2)/length(siteID),GOF_v36(:,3)/length(siteID),...
    'VariableNames',{'GenusID','GenusName','TP','TN','FP','FN','Gof','AccAS1a','AccAS1b','AccAS1c',...
    'AccAS2a','AccAS2b','AccAS2c','AccAS3a','AccAS3b','AccAS3c','GofAS1a','GofAS1b','GofAS1c',...
    'GofAS2a','GofAS2b','GofAS2c','GofAS3a','GofAS3b','GofAS3c'})

writetable(T,'source_data/Fig7.csv')

%% evaluate LossOfAccuracy
LossOfAccuracy=zeros(length(GenusName),3);
for g=1:length(GenusName)
    LossOfAccuracy(g,1)=mean(Accuracy_v12(g,:)-AccuracyAll(indFN(g)));
    LossOfAccuracy(g,2)=mean(Accuracy_v24(g,:)-AccuracyAll(indFN(g)));
    LossOfAccuracy(g,3)=mean(Accuracy_v36(g,:)-AccuracyAll(indFN(g)));
end
% mean (across genera) Loss of accuracy due to reduction in number of sampling sites
MeanLossOfAccuracy = mean(LossOfAccuracy)

T=table(GenusName,LossOfGOFcalib(:,1),LossOfGOFcalib(:,2),LossOfGOFcalib(:,3),...
    LossOfGOFvalid(:,1),LossOfGOFvalid(:,2),LossOfGOFvalid(:,3),...
    LossOfAccuracy(:,1),LossOfAccuracy(:,2),LossOfAccuracy(:,3),'VariableNames',...
    {'GenusName','LossOfGofCalibAS1','LossOfGofCalibAS2','LossOfGofCalibAS3',...
    'LossOfGofValidAS1','LossOfGofValidAS2','LossOfGofValidAS3',...
    'LossOfAccuracyAS1','LossOfAccuracyAS2','LossOfAccuracyAS3'});

writetable(T,'source_data/Table1.csv');

%% Figure distribution of stream order values at eDNA sampling sites
% the missing kicknet site has stream order 5
figure('units','centimeters','position',[0 0 21 6]); 
subplot(1,2,1); histogram(stream_order_reach(SitesReach),'facecolor',[0.5 0.5 0.5])
set(gca,'tickdir','out','xtick',[1:5]); box off
xlabel('Stream order'); ylabel('Number of sampling sites')
subplot(1,2,2); histogram(stream_order_reach,'facecolor',[0.5 0.5 0.5])
set(gca,'tickdir','out','xtick',[1:5]); box off
xlabel('Stream order'); ylabel('Number of reaches')


