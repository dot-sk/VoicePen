#include "arch/gigaam/window-plan.h"
#include "arch/gigaam/decoder.h"
#include <cassert>
#include <vector>
using namespace transcribe::gigaam;
int main() {
    for (int total : {1,624,625,626,627,1050,1051,2029,10000}) {
        auto plan=plan_windows(total);
        if(total<=625) {assert(plan.n_windows()==1);continue;}
        int covered=0;
        for(int i=0;i<plan.n_windows();++i) {
            int a=plan.bounds[i],b=plan.bounds[i+1];
            int ws=std::max(0,a-k_window_ctx_frames),we=std::min(total,b+k_window_ctx_frames);
            assert(a==covered && b>a && we-ws<=625 && a-ws<=50 && we-b<=50);
            covered=b;
        }
        assert(covered==total);
    }
    std::vector<int> ids={1,1,70,1,2,2,70,2};
    std::vector<float> logits(ids.size()*71,-10.f);
    for(size_t i=0;i<ids.size();++i)logits[i*71+ids[i]]=10.f;
    std::vector<int> tokens,frames;
    assert(collapse_ctc_logits(logits.data(),(int)ids.size(),71,tokens,frames)==TRANSCRIBE_OK);
    assert((tokens==std::vector<int>{1,1,2,2}));
    assert((frames==std::vector<int>{0,3,4,7}));
}
