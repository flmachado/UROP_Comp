function fast_conf_int,chi,adi,prop,chi_thr
  n_prop   = n_elements(prop)
  if n_prop gt 1 then begin
     chi_dim  = min(min(min(min(chi,dim=adi[0]),dim=adi[1]),$
                            dim=adi[2]),dim=adi[3])
     chi_reb  = REBIN(chi_dim,n_prop*100.)
     prop_reb = REBIN(prop,n_prop*100.)
     in       = where(chi_reb le chi_thr,n_in)
     if n_in gt 0 then begin
        l_prop = min(prop_reb(in))
        h_prop = max(prop_reb(in))
     endif else begin
        l_prop = prop_reb(where(chi_reb eq min(chi_reb)))
        h_prop = prop_reb(where(chi_reb eq min(chi_reb)))
     endelse
  endif else begin
     l_prop   = prop
     h_prop   = prop
  endelse
  return,[l_prop,h_prop]
end


function trapz1, x, y ; trapezoidal integration
  n = (size(x))[1]
  return, total((x[1:n-1] - x[0:n-2])*(y[1:n-1]+y[0:n-2]),1)/2.
end


FUNCTION fast_scale,flux,eflux,model,det,scale=scale,x_err=x_err,id=id

;...Calculate scale and chi^2 (loop is quicker)

n_dat  = n_elements(det)
chi    = 0.
wmm    = 0.
wfm    = 0.
n_z    = (SIZE(model))[1]
n_tau  = (SIZE(model))[2]
n_metal= (SIZE(model))[3]
n_age  = (SIZE(model))[4]
n_Av   = (SIZE(model))[5]

if KEYWORD_SET(x_err) then begin

   n_fl   = n_elements(eflux)
   eflux2 = sqrt((REBIN(eflux,n_fl,n_z))^2 + $
                 (x_err*(REBIN(flux,n_elements(flux),n_z)))^2 ) ; changes in eflux by the error parameter
    
   weight = TRANSPOSE(REFORM(REBIN(1./(eflux2*eflux2),n_fl,n_z,n_tau,n_metal,$
                                   n_age,n_Av),n_fl,n_z,n_tau,n_metal,n_age,$
                             n_Av),[1,2,3,4,5,0])
   wmm    = TOTAL((weight*model*model)[*,*,*,*,*,det],6)
   for k=0,n_dat-1 do begin 
      wfm = TEMPORARY(wfm) + weight(*,*,*,*,*,det(k)) $
      * TOTAL(flux(det(k))) * model(*,*,*,*,*,det(k))
   endfor
   scale  = wfm / wmm

   wfm    = [0] & wmm = [0] & weight = [0]
   
   eflux2 = TRANSPOSE(REFORM(REBIN(eflux2,n_fl,n_z,n_tau,n_metal,n_age,n_Av),$
                             n_fl,n_z,n_tau,n_metal,n_age,n_Av),[1,2,3,4,5,0])
   for k=0,n_dat-1 do begin
      tmp_chi = (TOTAL(flux(det(k))) - scale * model(*,*,*,*,*,det(k))) / $
                eflux2(*,*,*,*,*,det(k))
      chi     = TEMPORARY(chi)+tmp_chi*tmp_chi
      tmp_chi = [0]
   endfor

   eflux2 = [0]
   ;calculates chi^2 and the scaling factor
endif else begin
   
   weight = REFORM(1. / (eflux*eflux))
   for k=0,n_dat-1 do wmm = TEMPORARY(wmm) + TOTAL(weight(det(k))) * $
      model(*,*,*,*,*,det(k)) * model(*,*,*,*,*,det(k))
   for k=0,n_dat-1 do wfm = TEMPORARY(wfm) + TOTAL(weight(det(k))) * $
      TOTAL(flux(det(k))) * model(*,*,*,*,*,det(k))
   scale = wfm / wmm  ; calculates the scaling factor based on the model galaxies and the input (flux)
   wfm   = [0] & wmm = [0] 
   
   for k=0,n_dat-1 do begin
      tmp_chi = TOTAL(flux(det(k))/eflux(det(k))) - $
                1./TOTAL(eflux(det(k))) * scale * model(*,*,*,*,*,det(k))
      chi     = TEMPORARY(chi)+tmp_chi*tmp_chi ; calculates the chi^2 for each scalling
      tmp_chi = [0] 
   endfor
   
endelse

return,chi

END



PRO fast_fit,id,flux,eflux,zspec,zphot,model,mass_model,sfr_model,z,$
             log_tau,metal,log_age,A_v,name_out,filters,key,tmp_name,$
             C_INTERVAL=C_INTERVAL,N_SIM=N_SIM,AUTO_SCALE=AUTO_SCALE,$
             TEMP_ERR_FILE=TEMP_ERR_FILE,SAVE_CHI_GRID=SAVE_CHI_GRID,$
             BEST_FIT=BEST_FIT,scale_bands=scale_bands,OUTPUT_DIR=$
             OUTPUT_DIR,lambda=lambda

  if N_SIM ne 0 then n_int = N_ELEMENTS(C_INTERVAL) else n_int=0
  format  = '(i7,'+strtrim(1+2*n_int,1)+'(f10.4),'+strtrim(1+2*n_int,1)+$
            '(f10.2),'+strtrim(1+2*n_int,1)+'(f10.4),'+strtrim(2+4*n_int,1)+$
            '(f10.2),'+strtrim(4+8*n_int,1)+'(f10.2),(e10.2))'
  format2 = '(i7,'+strtrim(5+10*n_int,1)+'(i10),'+strtrim(4+8*n_int,1)+$
            '(i10),i10)'
  det     = where(flux ne -99,n_det)
  
  ;skip fitting if zphot=NAN: if .zout is given and both zph and zsp are 
  ;not defined (this is set in fast_read_observations)
  ;or if all bands have no detection
  if not FINITE(zphot(0), /NAN) and n_det gt 0 then begin
     
     if not KEYWORD_SET(N_SIM) then N_SIM=0 
     if N_SIM ne 0 and not KEYWORD_SET(C_INTERVAL) then C_INTERVAL=68
                              
     ;...Exclude bands that have no coverage (don't forget filters!)
     n_tau   = (SIZE(model))[2]
     n_metal = (SIZE(model))[3]
     n_age   = (SIZE(model))[4]
     n_Av    = (SIZE(model))[5]
     n_dat   = (SIZE(model))[6] ; for better understanding get the various values in seperate variables
                           
     ;...Reduce model grid to zspec or zphot if N_SIM=0
     if zspec ne -1 or (zphot(0) ge 0 and N_SIM eq 0) then begin
        cp_model = model & model = [0] & cp_z = z ; copy variables
        if zspec ne -1 then zslice = zspec ;define a new variable zslice
        if zspec eq -1 then zslice = zphot(0)
        ind_z = where(abs(z-TOTAL(zslice)) eq min(abs(z-TOTAL(zslice))),$
                      n_ind_z) ; find the value of z which is closes to the sum of zslice (?)
        ind_z = ROUND(TOTAL(ind_z)/n_ind_z) ; If more than one calculate average
        model = cp_model(ind_z,*,*,*,*,*)
        z     = cp_z(ind_z) ; reduces model to selected z
     endif
    
     ;...Reduce model grid between lzphot and hzphot for zphot & N_SIM!=0
     ;   if two confidence intervals are given, take outer!
     if zspec eq -1 and (zphot(0) ge 0 and N_SIM ne 0) then begin
        cp_model = model & model = [0] & cp_z = z ; create temporary variables
        good_z   = where(z ge zphot(1+2*(n_int-1)) and z le $
                         zphot(2+2*(n_int-1)),tmp_n_z)  ; What is the physical meaning of this?
        if tmp_n_z eq 0 then good_z = $
           where(abs(z-TOTAL(zphot(0))) eq min(abs(z-TOTAL(zphot(0)))))
        model    = cp_model(good_z,*,*,*,*,*) ; new model is the set of good values of z
        z        = cp_z(good_z) 
     endif
     n_z = n_elements(z)

     ;...Calculate extra error from template error function
     if KEYWORD_SET(TEMP_ERR_FILE) then if FILE_TEST(TEMP_ERR_FILE) then $
        begin
        f_err  = FAST_READ(TEMP_ERR_FILE,'flt',comment='#') ; error data
        fl_err = f_err(1,*)
        phot   = filters(0,UNIQ(filters(0,where(filters(3,*) eq 1))))
        n_phot = n_elements(phot) ; number of filters
        x_err  = fltarr(n_dat,n_z) ; 
        
        for i=0,n_z-1 do begin
           wl_err = f_err(0,*) * (1.+z(i)) 
           for j=0,n_phot-1 do begin
              filt_ind = where(filters(0,*) eq phot(j)) ;index of filter
              good_tr  = where(filters(2,filt_ind) gt 0.005) ; find positions where the filter is gt 0.005
              wl_filt  = REFORM(filters(1,filt_ind)) ; takes the first column of the filters
              tr_filt  = REFORM(filters(2,filt_ind)) ; second column of filters
              good_err = where(wl_err ge min(wl_filt) and $
                               wl_err le max(wl_filt)) ; places where error is between the filter values
              good_err = [min(good_err)-1,good_err,max(good_err)+1] ; adds an extra position before and after
              wl_err2  = wl_err(good_err) ; New array based on the previous position 
              fl_err2  = fl_err(good_err) ; Like before line
              tr_err   = INTERPOL(tr_filt,wl_filt,wl_err2) > 0 ; Interpolates tr_filt to positions of wl_err2
              fl_filt  = INTERPOL(fl_err,wl_err,wl_filt) > 0 ; Interpolate fl_err to positions of wl_filt
              wl_tot   = [wl_filt,wl_err2]
              i_sort   = SORT(wl_tot)
              wl_tot   = TEMPORARY(wl_tot(i_sort)) ; sorts wl_tot
              tr_tot   = ([tr_filt,tr_err])[i_sort] ; rearranges the array based on the sort of wl_tot
              fl_tot   = ([fl_filt,fl_err2])[i_sort]
              x_err(j,i) = trapz1(wl_tot,tr_tot*wl_tot*fl_tot) / $
                           trapz1(wl_tot,tr_tot*wl_tot) ;Calculates an error 
           endfor
        endfor
     endif
     
                                
     ;...Fit real observations
     if KEYWORD_SET(AUTO_SCALE) then begin
        as  = FAST_AUTO_SCALE(flux,eflux,filters,scale_bands=scale_bands,$
                              fit_bands=fit_bands,fscale=spec_scale) ; autoscale the observation to the data
        chi = FAST_SCALE(as.flux,as.eflux,model,fit_bands,$ 
                         scale=scale,x_err=x_err) ; calculate the chi^2 ans sets a scaling 
     endif else begin
        chi = FAST_SCALE(flux,eflux,model,det,scale=scale,x_err=x_err,id=id)
     endelse
     chi  = REFORM(chi,n_z,n_tau,n_metal,n_age,n_Av) ; ensure chi array is of correct size

     i_zb = where(abs(z-zphot(0)) eq min(abs(z-zphot(0))),n_i_zb) ; find z where it is closest to zphot
     i_zb = ROUND(TOTAL(TEMPORARY(i_zb))/n_i_zb) ; if more than one find average
     

     ;...Make full mass and sfr grid
     n_all  = [n_tau,n_metal,n_age,n_Av,n_z]
     n_all2 = [n_z,n_tau,n_metal,n_age,n_Av]
     mass   = REFORM(TRANSPOSE(REFORM(REBIN(mass_model,n_all),n_all),$
                               [4,0,1,2,3]) * scale,n_all2)
     sfr    = REFORM(TRANSPOSE(REFORM(REBIN(sfr_model,n_all),n_all),$
                               [4,0,1,2,3]) * scale,n_all2)    
     
                                
     ;...Derive best-fit values, can be fast min.val=min(array,i_min)
     if zphot(0) ne -1 and zspec eq -1 and N_SIM ne 0 then tmp_sol = $
        where(chi(i_zb,*,*,*,*) eq min(chi(i_zb,*,*,*,*),/NAN),n_sol) else $
           tmp_sol = where(chi eq min(chi,/NAN),n_sol) ; find the solutions
     
     if n_sol eq 0 then begin
        
        print,"    WARNING: no solution for object "+strtrim(id,1)
        print,"             check whether all photometric erros are non-zero"
        printf,1,format=format2,id,REPLICATE(-1,9+n_int*9*2+1)
        
     endif else begin
        
        tmp_sol  = ROUND(TOTAL(TEMPORARY(tmp_sol))/n_sol)    ; find average of the positions?
        if zphot(0) ne -1 and zspec eq -1 and N_SIM ne 0 then begin
           b_val    = array_indices(chi(i_zb,*,*,*,*),tmp_sol) ; b_val are the positions of the solutions
           b_val(0) = i_zb ; the first position has to be i_zb
           b_z      = zphot(0)
           min_chi  = min(chi(i_zb,*,*,*,*),/NAN)
        endif else begin
           b_val    = array_indices(chi,tmp_sol)
           b_z      = z(b_val(0))
           min_chi  = min(chi,/NAN)
        endelse
        b_ltau  = log_tau(b_val(1))
        b_metal = metal(b_val(2))
        b_lage  = log_age(b_val(3))
        b_Av    = A_v(b_val(4))
        b_mass  = mass(b_val(0),b_val(1),b_val(2),b_val(3),b_val(4))
        b_lmass = ALOG10(b_mass)
        b_sfr   = sfr(b_val(0),b_val(1),b_val(2),b_val(3),b_val(4))
        b_ssfr  = b_sfr / b_mass
        b_efold = b_lage - b_ltau ; constants of the solutions ?
        if b_sfr eq 0 then b_lsfr = -99 else b_lsfr = Alog10(b_sfr)
        if b_ssfr eq 0 then b_lssfr = -99 else b_lssfr = Alog10(b_ssfr)
        best    = [b_z,b_ltau,b_metal,b_lage,b_Av,b_lmass,b_lsfr,b_lssfr,$
                   b_efold] ; best solution are the ones with these values
        b_scale = scale(b_val(0),b_val(1),b_val(2),b_val(3),b_val(4)) ; get the scalling factor of the solution
        scale   = [0]

                                
        ;...fit Monte Carlo simulations
        if N_SIM gt 0 then begin
           
           sol_sim = fltarr(N_SIM,5) ;z,tau,metal,age,Av
           chi_sim = fltarr(N_SIM)
           fl_sim  = fltarr(n_dat)
           
           ;...Reduce model grid when zphot is know
           if zphot(0) ne -1 and zspec eq -1 then model = $
              TEMPORARY(model(i_zb,*,*,*,*,*))
           
           for i=0,N_SIM-1 do begin

               ;...Make and fit monte carlo simulations
               ;   If zphot are given, MC are all performed at best z_phot
              if n_elements(x_err) ne 0 then begin
                 exflux = sqrt(eflux^2+(x_err(*,i_zb)*flux)^2) 
              endif else exflux = eflux
              for j=0,n_dat-1 do fl_sim(j) = flux(j)+randomn(seed)*exflux(j)
              
              if KEYWORD_SET(AUTO_SCALE) then begin
                 as      = FAST_AUTO_SCALE(fl_sim,eflux,filters)
                 tmp_chi = FAST_SCALE(as.flux,as.eflux,model,fit_bands,$
                                      x_err=x_err)
              endif else begin
                 tmp_chi = FAST_SCALE(fl_sim,eflux,model,det,x_err=x_err)
              endelse
              tmp_min = where(tmp_chi eq min(tmp_chi,/NAN),n_min)
              if n_min eq 0 then begin
                 chi_sim(i) = 1.e9 
              endif else begin
                 sol_sim(i,*) = array_indices(tmp_chi,tmp_min[0])
                 if zphot(0) ne -1 then sol_sim(i,0) = i_zb
                 chi_sim(i) = chi(sol_sim(i,0),sol_sim(i,1),sol_sim(i,2),$
                                  sol_sim(i,3),sol_sim(i,4))
              endelse  ; a different fitting method (monte carlo method). run N simulation and from that judge the results
           endfor
           
           ;...Derive confidence intervals
           low    = fltarr(n_int,9)
           high   = fltarr(n_int,9)
           efold  = TRANSPOSE(REBIN(log_age,n_age,n_tau)) - $
                    REBIN(log_tau,n_tau,n_age)
           i_sort  = SORT(chi_sim)
           chi_sim = chi_sim(i_sort)
           chi_thr = fltarr(n_int)
           
           for k=0,n_int-1 do begin
                
              chi_thr(k) = INTERPOL(chi_sim,findgen(n_sim),$
                                    C_INTERVAL(k)/100.*n_sim-1.)

              ;...Reduce grid for zphot and two or more confidence intervals
              if zphot(0) ne -1 and zspec eq -1 and k lt n_int-1 then begin
                 good_z  = where(z ge zphot(1+2*(n_int-1)) and z $
                                 le zphot(2+2*(n_int-1)),n_z)
                 cp_chi  = chi
                 cp_mass = mass
                 cp_sfr  = sfr
                 chi     = cp_chi(good_z,*,*,*,*)
                 sfr     = cp_sfr(good_z,*,*,*,*)
                 mass    = cp_mass(good_z,*,*,*,*)
              endif
              ssfr = sfr / mass
              
              if zphot(0) ne -1 and zspec eq -1 then begin
                 diff       = min(chi(i_zb,*,*,*,*),/NAN) - min(chi,/NAN)
                 chi_thr(k) = chi_thr(k) - diff
              endif
              

              in_int  = where(chi le chi_thr(k) or chi eq min(chi,/NAN), $
                              n_grid)
              grid_1s = array_indices(chi,in_int)
              if zphot(0) ne -1 and zspec eq -1 then begin
                 l_z = zphot(1+2*k)
                 h_z = zphot(2+2*k)
              endif else begin
                 l_z = min(z(grid_1s(0,*)))
                 h_z = max(z(grid_1s(0,*)))
              endelse

              l_lmass = Alog10(min(mass(grid_1s(0,*),grid_1s(1,*),$
                                        grid_1s(2,*),grid_1s(3,*),$
                                        grid_1s(4,*)))) < b_lmass
              h_lmass = Alog10(max(mass(grid_1s(0,*),grid_1s(1,*),$
                                        grid_1s(2,*),grid_1s(3,*),$
                                        grid_1s(4,*)))) > b_lmass
              l_sfr   = min(sfr(grid_1s(0,*),grid_1s(1,*),grid_1s(2,*),$
                                grid_1s(3,*),grid_1s(4,*))) < b_sfr
              h_sfr   = max(sfr(grid_1s(0,*),grid_1s(1,*),grid_1s(2,*),$
                                grid_1s(3,*),grid_1s(4,*))) > b_sfr
              l_ssfr  = min(ssfr(grid_1s(0,*),grid_1s(1,*),grid_1s(2,*),$
                                 grid_1s(3,*),grid_1s(4,*))) < b_ssfr
              h_ssfr  = max(ssfr(grid_1s(0,*),grid_1s(1,*),grid_1s(2,*),$
                                 grid_1s(3,*),grid_1s(4,*))) > b_ssfr
              l_efold = min(efold(grid_1s(1,*),grid_1s(3,*))) < b_efold
              h_efold = max(efold(grid_1s(1,*),grid_1s(3,*))) > b_efold
              
              ci_av   = fast_conf_int(chi,[1,1,1,1],A_v,chi_thr(k))
              l_Av    = ci_av[0]
              h_Av    = ci_av[1]
              ci_met  = fast_conf_int(chi,[1,1,2,2],metal,chi_thr(k))
              l_metal = ci_met[0]
              h_metal = ci_met[1]
              ci_lage = fast_conf_int(chi,[1,1,1,2],log_age,chi_thr(k))
              l_lage  = ci_lage[0]
              h_lage  = ci_lage[1]
              ci_ltau = fast_conf_int(chi,[1,2,2,2],log_tau,chi_thr(k))
              l_ltau  = ci_ltau[0]
              h_ltau  = ci_ltau[1]

              if l_sfr eq 0 then l_lsfr = -99 else l_lsfr = Alog10(l_sfr)
              if h_sfr eq 0 then h_lsfr = -99 else h_lsfr = Alog10(h_sfr)
              if l_ssfr eq 0 then l_lssfr = -99 else l_lssfr = Alog10(l_ssfr)
              if h_ssfr eq 0 then h_lssfr = -99 else h_lssfr = Alog10(h_ssfr)
              
              low(k,*)  = [l_z,l_ltau,l_metal,l_lage,l_Av,l_lmass,l_lsfr,$
                           l_lssfr,l_efold]
              high(k,*) = [h_z,h_ltau,h_metal,h_lage,h_Av,h_lmass,h_lsfr,$
                           h_lssfr,h_efold]
              
              if zphot(0) ne -1 and zspec eq -1 and k lt n_int-1 then begin
                 chi  = cp_chi  & cp_chi  = [0]
                 mass = cp_mass & cp_mass = [0]
                 sfr  = cp_sfr  & cp_sfr  = [0]
              endif 
              
           endfor
           
        endif else begin
           chi_thr = -1
           low     = -1
           high    = -1
        endelse
        
        ;...Print values
        CASE n_int OF
           0: all = best
           1: all = REFORM(TRANSPOSE([[best],[REFORM(low)],[REFORM(high)]]),$
                           9*(2*n_int+1))
           2: all = REFORM(TRANSPOSE([[best],[REFORM(low(0,*))],$
                                      [REFORM(high(0,*))],[REFORM(low(1,*))],$
                                      [REFORM(high(1,*))]]),9*(2*n_int+1))
        ENDCASE
        deg_fix = 0.
        if n_Av gt 1 then deg_fix = deg_fix+1.
        if n_age gt 1 then deg_fix = deg_fix+1.
        if n_metal gt 1 then deg_fix = deg_fix+1.
        if n_tau gt 1 then deg_fix = deg_fix+1.
        if n_z gt 1 then deg_fix = deg_fix+1

        n_degree = n_det - deg_fix 
        printf,1,format=format,id,all,min_chi / n_degree
        
        if keyword_set(SAVE_CHI_GRID) then begin
           if n_elements(cp_z) eq 0 then i_best = b_val else $
              i_best = [where(cp_z eq best(0)),b_val(1:4)]
           if n_elements(spec_scale) ne 0 then begin
              SAVE,chi,n_degree,mass,sfr,z,chi_thr,best,i_best,low,high,b_scale,key,$
                   spec_scale,FILENAME=tmp_name+'/chi_'+name_out+'.'+$
                   strtrim(id,1)+'.save'
           endif else begin
              SAVE,chi,n_degree,mass,sfr,z,chi_thr,best,i_best,low,high,b_scale,key,$
                   FILENAME=tmp_name+'/chi_'+name_out+'.'+strtrim(id,1)+$
                   '.save'
           endelse
        endif
        
        ;best fit at the input resolution
        best_lfit = b_scale*reform(model(where(z eq best(0)),where(log_tau eq best(1)),$
                                         where(metal eq best(2)),where(log_age eq best(3)),$
                                         where(A_V eq best(4)),*)) ; solution with the scalling factor

        if KEYWORD_SET(BEST_FIT) then FAST_BEST_FIT, OUTPUT_DIR, name_out, $
           id, key, best, b_scale, lambda, best_lfit  ; calculates best fit and saves it
        
     endelse
     
     if zspec ne -1 or zphot(0) ge 0 then begin
        model    = cp_model
        cp_model = [0]
        z        = cp_z
     endif
     
  endif else begin
     
     printf,1,format=format2,id,REPLICATE(-1,9+2*n_int*9+1)
     
  endelse
  
  
END
