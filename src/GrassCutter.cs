using UnityEngine;
using UnityEngine.Experimental.Rendering;



class GrassCutter : GrassRendererRT._GrassCutter
{
    [SerializeField] private float radius;
    public override float Radius {
        get {
            return radius;
        }
    }

    private void Update()
    {
        _addCutter();
    }
}
