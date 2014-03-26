PRO fast_best_fit, DIR, NAME, ID, KEY, BEST, SCALE, LAMBDA, BEST_LFIT

junk    = CHECK_MATH()

for i=0,n_elements(key)-1 do r=execute(key[i])

if not KEYWORD_SET(MY_SFH) then begin
   ised    = LIBRARY_DIR+'/ised_'+SFH+'.'+RESOLUTION+'/'+$
             LIBRARY+'_'+RESOLUTION+'_'+IMF+$
             repstr(string(BEST[2],f='(g0)'),'0.','_z')+'_ltau'+$
             strtrim(string(BEST[1],f='(f5.1)'),1)+'.ised'
endif else begin
   ised    = LIBRARY_DIR+'/'+LIBRARY+'_'+RESOLUTION+'_'+IMF+$
             repstr(string(BEST[2],f='(g0)'),'0.','_z')+'_'+MY_SFH+$
             '.ised'
endelse

synspec = FAST_READ_MODEL(ised,BEST(3),wl)
synspec = FAST_DUST(temporary(synspec),wl,BEST(4),law=DUST_LAW,$
                    E_B=E_B,delta=delta)
junk    = CHECK_MATH()
synspec = FAST_LUM2FLUX(BEST(0)) * FAST_MADAU(TEMPORARY(synspec),wl,BEST(0))
synspec = REFORM(SCALE * TEMPORARY(synspec) / (10^((25.+48.57)/2.5 - 19.)))
wl_obs  = (1.+BEST(0))*wl

if not file_test(DIR+'/BEST_FITS') then file_mkdir, DIR+'/BEST_FITS'

Close,5
openw,5,DIR+'/BEST_FITS/'+NAME+'_'+strtrim(ID,1)+'.fit'
printf,5,'# wl fl (x 10^-19 ergs s^-1 cm^-2 Angstrom^-1)'
for i=0,n_elements(wl)-1 do printf,5,wl_obs(i),synspec(i)
close,5

best_lfit = best_lfit / (10^((25.+48.57)/2.5 - 19.))
openw,6,DIR+'/BEST_FITS/'+NAME+'_'+strtrim(ID,1)+'.input_res.fit'
printf,6,'# wl fl (x 10^-19 ergs s^-1 cm^-2 Angstrom^-1)'
for i=0,n_elements(lambda)-1 do printf,6,lambda(i),best_lfit(i)
close,6

END
