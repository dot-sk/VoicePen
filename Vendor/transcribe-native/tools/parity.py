"""Frozen numerical gates and independent stock25 reference planning."""
import numpy as np

POLICY='stock25-v1'

def validate_policy(native,reference):
    if native != reference or native not in {POLICY,'whole-input-diagnostic'}:
        raise ValueError('mismatched or unknown context policy')

def window_plan(frames):
    if frames<=0: raise ValueError('nonpositive encoder length')
    if frames<=625: return [(0,frames,0,frames)]
    count=(frames+524)//525
    bounds=[frames*i//count for i in range(count+1)]
    return [(a,b,max(0,a-50),min(frames,b+50)) for a,b in zip(bounds,bounds[1:])]

def collapse(ids,blank):
    out=[]
    previous=None
    for token in ids:
        token=int(token)
        if token!=blank and token!=previous: out.append(token)
        previous=token
    return out

def compare(native,reference,stage,storage):
    a=np.asarray(native,dtype=np.float64)
    b=np.asarray(reference,dtype=np.float64)
    result={'stage':stage,'storage':storage,'shape':list(a.shape),'reference_shape':list(b.shape),'pass':False}
    if a.shape!=b.shape or a.size==0:
        return {**result,'reason':'shape'}
    if not np.isfinite(a).all() or not np.isfinite(b).all():
        return {**result,'reason':'nonfinite'}
    error=a-b
    rms=float(np.sqrt(np.mean(error**2)))
    reference_rms=float(np.sqrt(np.mean(b**2)))
    nrmse=rms/max(reference_rms,1e-6)
    denom=float(np.linalg.norm(a.ravel())*np.linalg.norm(b.ravel()))
    cosine=float(np.dot(a.ravel(),b.ravel())/denom) if denom else None
    if stage=='mel': passed=bool(np.all(np.abs(error)<=1e-4+1e-4*np.abs(b)))
    elif reference_rms<=1e-6: passed=rms<=1e-6
    else:
        tolerance,minimum=(1e-3,.99999) if storage=='F32' else (1e-2,.9999)
        passed=nrmse<=tolerance and cosine is not None and cosine>=minimum
    return {**result,'rms':rms,'nrmse':nrmse,'cosine':cosine,'max_abs':float(np.abs(error).max()),'pass':passed}
