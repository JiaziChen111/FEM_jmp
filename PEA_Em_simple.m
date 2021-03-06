%% Housekeeping
clear all
close all
clc
format long

%% Set the stage
addpath(genpath('param'));
addpath(genpath('tools'));
mypara_simple;

damp_factor = 0.4;
T = 20000;
burnin = ceil(0.05*T);
maxiter = 100000;
tol = 1e-6;
ksim = zeros(1,T);
esim = ksim;
Asim = ksim;
mksim = ksim;
mesim = ksim;
Emksim = ksim;
Emesim = ksim;
qsim = ksim;
nsim = ksim;

if (exist('PEA_Em.mat','file')==2)
    load('PEA_Em.mat','coeff_mk','coeff_me')
else
    coeff_mk = [1.08;-0.12;-0.40;-0.115]; % one constant, each for state variable
    coeff_me = [0.78;-0.18;-0.36;-0.109];
end

% coeff_mf = [-2.57+0.37*(7.25)+1.67*(-0.006); +3.06; -0.37];

coeff_mk_old = coeff_mk;
coeff_me_old = coeff_me;
regeqn_mk = @(b,x) exp(b(1)*x(:,1)+b(2).*log(x(:,2))+b(3).*log(x(:,3))+b(4).*log(x(:,4))); % Model
regeqn_me = @(b,x) exp(b(1)*x(:,1)+b(2).*log(x(:,2))+b(3).*log(x(:,3))+b(4).*log(x(:,4))); % Model

%% Simulate shocks
rng('default')
eps = normrnd(0,1,1,T);
for t = 2:T
    Asim(t) = rrho_z*Asim(t-1) + ssigma_z*eps(t);
end
Abar = 1;
Asim = Abar*exp(Asim);

%% Iteration
diff = 10; iter = 0;
while (diff>damp_factor*tol && iter <= maxiter)
% Simulation endo variables
ksim(1) = kbar; esim(1) = ebar;
for t = 1:T
	% load current state
    state(1) = Asim(t);
    state(2) = ksim(t);
    state(3) = esim(t);
    EM = exp([1 log(state)]*[coeff_mk coeff_me]);
	A = state(1); k = state(2); e = state(3);
	
	% find control vars
	control = state2control_simple(state,coeff_mk,coeff_me,param);
	
    % Find mk and me;
    mksim(t) = control.mk;
    mesim(t) = control.me;
	
	% find derived vars
	qsim(t) = control.q;
	nsim(t) = control.n;
    
    if (t<T)
		% Find predetermined next state
		esim(t+1) = control.eplus;
		ksim(t+1) = control.kplus;
        
        % Find expected mf and mh
        [n_nodes,epsi_nodes,weight_nodes] = GH_Quadrature(10,1,1);
        Emk = 0; Eme = 0;
        for i_node = 1:length(weight_nodes)
            Aplus = exp(rrho_z*log(Asim(t)) + ssigma_z*epsi_nodes(i_node));
            stateplus(1) = Aplus;
            stateplus(2) = ksim(t+1);
            stateplus(3) = esim(t+1);
			kplus = stateplus(2); eplus = stateplus(3);
						
			% find control vars at t+1
			controlplus = state2control_simple(stateplus,coeff_mk,coeff_me,param);
            Emk = Emk + weight_nodes(i_node)*(controlplus.mk);
            Eme = Eme + weight_nodes(i_node)*(controlplus.me);
        end
        Emksim(t) = Emk;
        Emesim(t) = Eme;
	end
	
end

%% Get temp coeff
ln_mk = log(Emksim(burnin+1:end-1)');
ln_me = log(Emesim(burnin+1:end-1)');
X = [ones(T-burnin-1,1) log(Asim(burnin+1:end-1)') log(ksim(burnin+1:end-1)') log(esim(burnin+1:end-1)')];
coeff_mk_temp = (X'*X)\(X'*ln_mk);
coeff_me_temp = (X'*X)\(X'*ln_me);

%% Damped update
coeff_mk_new = damp_factor*coeff_mk_temp+(1-damp_factor)*coeff_mk;
coeff_me_new = damp_factor*coeff_me_temp+(1-damp_factor)*coeff_me;

%% Compute norm
diff = norm([coeff_mk;coeff_me]-[coeff_mk_new;coeff_me_new],Inf);

%% Update
coeff_mk = coeff_mk_new;
coeff_me = coeff_me_new;
iter = iter+1;
%% Display something
iter
diff
coeff_mk
coeff_me

end;

%% Check Regression Accuracy
md_mk = fitlm(X(:,2:end),ln_mk,'linear','RobustOpts','on')
md_me = fitlm(X(:,2:end),ln_me,'linear','RobustOpts','on')

save('trad_PEA_simple.mat')
%% Euler equation error
nk = 50; nA = 50; ne = 50;
Kgrid = linspace(0.8*kss,1.2*kss,nk);
Agrid = linspace(0.8,1.2,nA);
Ngrid = linspace(0.7,0.999,ne);
EEerror = 999999*ones(nA,nk,ne);
for i_A = 1:nA
    A = Agrid(i_A);
    for i_k = 1:nk
        k = Kgrid(i_k);
        for i_n = 1:ne
            n = Ngrid(i_n);
            state(1) = A;
            state(2) = k;
            state(3) = n;
            EM = exp([1 log(state)]*[coeff_mh coeff_mf]);
            
            y = A*(k)^(aalpha)*(n)^(1-aalpha);
            c = (bbeta*EM(1))^(-1);
            ttheta = (kkappa/(c*xxi*bbeta*EM(2)))^(1/(eeta-1));
            v = ttheta*(1-n);
            kplus = y - c +(1-ddelta)*k - kkappa*v;
            nplus = (1-x)*n + xxi*ttheta^(eeta)*(1-n);
            
            % Find expected mf and mh and implied consumption
            [n_nodes,epsi_nodes,weight_nodes] = GH_Quadrature(10,1,1);
            Emf = 0; Emh = 0;
            for i_node = 1:length(weight_nodes)
                Aplus = exp(rrho_A*log(A) + ssigma_A*epsi_nodes(i_node));
                state(1) = Aplus;
                state(2) = kplus;
                state(3) = nplus;
                EM = exp([1 log(state)]*[coeff_mh coeff_mf]);
                yplus = Aplus*(kplus)^(aalpha)*(nplus)^(1-aalpha);
                cplus = (bbeta*EM(1))^(-1);
                tthetaplus = (kkappa/(cplus*xxi*bbeta*EM(2)))^(1/(eeta-1));
                Emh = Emh + weight_nodes(i_node)*((1-ddelta+aalpha*yplus/kplus)/cplus);
                Emf = Emf + weight_nodes(i_node)*(( (1-ttau)*((1-aalpha)*yplus/nplus-z-ggamma*cplus) + (1-x)*kkappa/xxi*tthetaplus^(1-eeta) - ttau*kkappa*tthetaplus )/cplus );
            end
            c_imp = (bbeta*Emh)^(-1);
            EEerror(i_A,i_k,i_n) = abs((c-c_imp)/c_imp);
        end
    end
end
EEerror_inf = norm(EEerror(:),inf);
EEerror_mean = mean(EEerror(:));
figure
plot(Kgrid,EEerror(ceil(nA/2),:,ceil(ne/2)))

%% Implied policy functions and find wages
Agrid = csvread('../code/201505181149/results/Agrid.csv');
Kgrid = csvread('../code/201505181149/results/Kgrid.csv');
Ngrid = csvread('../code/201505181149/results/Ngrid.csv');
nA = length(Agrid);
nk = length(Kgrid);
ne = length(Ngrid);

kk = zeros(nA,nk,ne);
cc = kk;
vv = kk;
nn = kk;
ttheta_export = kk;
wage_export = kk;
cc_dynare = kk;
kk_dynare = kk;
nn_dynare = kk;
vv_dynare = kk;

mmummu = kk;
for i_k = 1:nk
    for i_n = 1:ne
        for i_A = 1:nA
            state(1) = Agrid(i_A); A = state(1);
            state(2) = Kgrid(i_k); k = state(2);
            state(3) = Ngrid(i_n); n = state(3);
            EM = exp([1 log(state)]*[coeff_mh coeff_mf]);
            
            y = A*(k)^(aalpha)*(n)^(1-aalpha);
            c = (bbeta*EM(1))^(-1);
            ttheta = (kkappa/(c*xxi*bbeta*EM(2)))^(1/(eeta-1));
            v = ttheta*(1-n);
            mh = (1-ddelta+aalpha*y/k)/c;
            mf = ( (1-ttau)*((1-aalpha)*y/n-z-ggamma*c) + (1-x)*kkappa/xxi*ttheta^(1-eeta) - ttau*kkappa*ttheta )/c;
            w = ttau*A*k^(aalpha)*(1-aalpha)*n^(-aalpha) + (1-ttau)*(z+ggamma*c) + ttau*kkappa*ttheta;
    
            kk(i_A,i_k,i_n) = y - c +(1-ddelta)*k - kkappa*v;
            nn(i_A,i_k,i_n) = (1-x)*n + xxi*ttheta^(eeta)*(1-n);
            cc(i_A,i_k,i_n) = c;
            vv(i_A,i_k,i_n) = v;
            
            cc_dynare(i_A,i_k,i_n) = exp(2.111091 + 0.042424/rrho*log(Agrid(i_A))/ssigma + 0.615500*(log(Kgrid(i_k))-log(k_ss)) + 0.014023*(log(Ngrid(i_n))-log(n_ss)) );
            kk_dynare(i_A,i_k,i_n) = exp(7.206845 + 0.006928/rrho*log(Agrid(i_A))/ssigma + 0.997216*(log(Kgrid(i_k))-log(k_ss)) + 0.005742*(log(Ngrid(i_n))-log(n_ss)) );
            nn_dynare(i_A,i_k,i_n) = exp(-0.056639 + 0.011057/rrho*log(Agrid(i_A))/ssigma + 0.001409*(log(Kgrid(i_k))-log(k_ss)) + 0.850397*(log(Ngrid(i_n))-log(n_ss)) );
            
            % Export prices
            wage_export(i_A,i_k,i_n) = w;
            ttheta_export(i_A,i_k,i_n) = ttheta;
        end
    end
end
save('PEA_Em.mat');
csvwrite('../code/201505181149/wage_export.csv',wage_export(:));
csvwrite('../code/201505181149/ttheta_export.csv',ttheta_export(:));
csvwrite('../code/201505181149/cPEA_export.csv',cc(:));
csvwrite('../code/201505181149/kPEA_export.csv',kk(:));
csvwrite('../code/201505181149/nPEA_export.csv',nn(:));


i_mid_n = ceil(ne/2);
i_mid_A = ceil(nA/2);
linewitdh=1.5;
figure
plot(Kgrid,squeeze(kk(i_mid_A,:,i_mid_n)),Kgrid,squeeze(kk_dynare(i_mid_A,:,i_mid_n)),'LineWidth',linewitdh)
axis('tight')
xlabel('k(t)')
ylabel('k(t+1)')
legend('Nonlinear','Linear')

figure
plot(Kgrid,squeeze(nn(i_mid_A,:,i_mid_n)),Kgrid,squeeze(nn_dynare(i_mid_A,:,i_mid_n)),'LineWidth',linewitdh)
axis('tight')
xlabel('k(t)')
ylabel('n(t+1)')
legend('Nonlinear','Linear')

figure
plot(Kgrid,squeeze(cc(i_mid_A,:,i_mid_n)),Kgrid,squeeze(cc_dynare(i_mid_A,:,i_mid_n)),'LineWidth',linewitdh)
axis('tight')
xlabel('k(t)')
ylabel('c(t)')
legend('Nonlinear','Linear')

figure
plot(Kgrid,squeeze(wage_export(i_mid_A,:,i_mid_n)),'LineWidth',linewitdh)
axis('tight')
xlabel('k(t)')
ylabel('wage')
legend('Nonlinear')

figure
plot(Kgrid,squeeze(ttheta_export(i_mid_A,:,i_mid_n)),'LineWidth',linewitdh)
axis('tight')
xlabel('k(t)')
ylabel('Tightness')
legend('Nonlinear')

%% Ergodic set where art thou?
    figure
    scatter3(Asim,ksim,esim)
    xlabel('Productivity')
    ylabel('Capital')
    zlabel('Employment')

%% Dynamics
Aindex = ceil(nA/2);
figure
[Kmesh,Nmesh] = meshgrid(Kgrid,Ngrid);
DK = squeeze(kk(Aindex,:,:))-Kmesh';
DN = squeeze(nn(Aindex,:,:))-Nmesh'
quiver(Kmesh',Nmesh',DK,DN,2)
axis tight

%% Paths 1
T = 5000; scale = 0;
A = 0.6;
k1 = zeros(1,T); n1 = zeros(1,T);
k1(1) = 1100; n1(1) = 0.90;
for t = 1:T
    state = [A k1(t) n1(t)];
    EM = exp([1 log(state)]*[coeff_mh coeff_mf]);
    y = A*(k1(t))^(aalpha)*(n1(t))^(1-aalpha);
    c = (bbeta*EM(1))^(-1);
    ttheta = (kkappa/(c*xxi*bbeta*EM(2)))^(1/(eeta-1));
    v = ttheta*(1-n1(t));
    
    if t < T
    k1(t+1) = y - c +(1-ddelta)*k1(t) - kkappa*v;
    n1(t+1) = (1-x)*n1(t) + xxi*ttheta^(eeta)*(1-n1(t));
    end
end
xx = k1; y = n1;
u = [k1(2:end)-k1(1:end-1) 0];
v = [n1(2:end)-n1(1:end-1) 0];

figure
quiver(xx,y,u,v,scale,'Linewidth',0.3);

save('PEA_Em.mat');























































