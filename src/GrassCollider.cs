using UnityEngine;
using UnityEngine.Experimental.Rendering;



class GrassCollider : GrassRendererRT._GrassCollider
{
    [SerializeField] private float radius;
    public override float Radius {
        get {
            return radius;
        }
    }

    private void Update()
    {
        _addCollider();
    }
}